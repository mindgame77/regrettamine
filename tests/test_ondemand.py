"""Paid on-demand research: 1 credit on an unchecked or partial page -> one job per firm, paid lane, claimed only by
toxy-researcher-3, done on valid research, refunded after 24 h, emails via the outbox."""
import json
import os
import uuid

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")

PAYLOAD = {
    "coverage": [{"checklist_item": "registration x firm", "status": "records", "query_ids": ["q1"], "record_ids": ["r1"]}],
    "search_log": [{"query_id": "q1", "tool": "form_adv", "query": "x", "executed_at": "2026-10-20T15:00:00Z"}],
    "records": [{"record_id": "r1", "field_path": "legal_entities",
                 "value": {"crd": "998401", "kind": "adviser", "registration_status": "SEC registered, Approved"}}],
}


def _j(v):
    return v if isinstance(v, (dict, list)) else json.loads(v)


def test_paid_research_lifecycle():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("insert into research_queue (registry_id, name, sec_crd, priority, status) values "
                    "('zz-od1', 'ZZ WOMBAT PARTNERS LLC', '998401', 900000, 'queued'), ('zz-od0', 'Zz Normal', null, -10, 'queued')")
        fid, slug = cur.execute("select id, slug from firms where registry_id = 'zz-od1'").fetchone()
        a1, a2 = str(uuid.uuid4()), str(uuid.uuid4())
        # a page view only reads: no spend, no request, no reordering
        assert _j(cur.execute("select firm_page(%s, %s, false)", (slug, a1)).fetchone()[0])["ondemand"] is None
        assert cur.execute("select count(*) from research_requests where firm_id = %s", (fid,)).fetchone()[0] == 0
        # two people pay: one job, two requests, paid lane at the front
        for a in (a1, a2):
            P = _j(cur.execute("select firm_page(%s, %s, true)", (slug, a)).fetchone()[0])
            assert P["status"] == "ok" and P["ondemand"] == {**P["ondemand"], "status": "queued", "mine": True, "missing": 10}
        assert cur.execute("select count(*) from ondemand_jobs where firm_id = %s", (fid,)).fetchone()[0] == 1
        assert cur.execute("select count(*), count(distinct job_id) from research_requests where firm_id = %s", (fid,)).fetchone() == (2, 1)
        lane, prio = cur.execute("select lane, priority from research_queue where registry_id = 'zz-od1'").fetchone()
        assert lane == "paid" and prio < -10
        # paying again on the same page never charges twice
        cur.execute("select firm_page(%s, %s, true)", (slug, a1))
        assert cur.execute("select count(*) from check_events where firm_id = %s", (fid,)).fetchone()[0] == 2
        # signed-out requester leaves an email on the open request
        assert _j(cur.execute("select notify_when_checked(%s, 'Test@Example.com', %s)", (slug, a1)).fetchone()[0])["status"] == "ok"
        assert cur.execute("select count(*) from check_requests where firm_id = %s", (fid,)).fetchone()[0] == 0
        # other bots never see the paid lane; toxy-researcher-3 gets it, one at a time
        assert "zz-od1" not in [r[0] for r in cur.execute("select registry_id from research_claim('toxy-researcher-1', 5)").fetchall()]
        assert [r[0] for r in cur.execute("select registry_id from research_claim('toxy-researcher-3', 5)").fetchall()] == ["zz-od1"]
        # paid lane empty: toxy-researcher-3 falls through to normal (non-paid) work
        nxt = [r[0] for r in cur.execute("select registry_id from research_claim('toxy-researcher-3', 5)").fetchall()]
        assert "zz-od1" not in nxt
        info = _j(cur.execute("select ondemand_job_info(array['zz-od1'])").fetchone()[0])["zz-od1"]
        assert info["paid"] and info["requesters"] == 2 and len(info["missing_checks"]) == 10
        assert _j(cur.execute("select firm_page(%s, %s, false)", (slug, a2)).fetchone()[0])["ondemand"]["status"] == "in_progress"
        # valid research -> done, back to normal lane, both keep the page, email queued for the one with an email
        cur.execute("insert into research_submissions (registry_id, bot_id, payload, valid) values ('zz-od1', 'toxy-researcher-3', %s, true)", (json.dumps(PAYLOAD),))
        assert cur.execute("select status from ondemand_jobs where firm_id = %s", (fid,)).fetchone()[0] == "done"
        assert cur.execute("select lane from research_queue where registry_id = 'zz-od1'").fetchone()[0] == "normal"
        for a in (a1, a2):
            P = _j(cur.execute("select firm_page(%s, %s, false)", (slug, a)).fetchone()[0])
            assert P["status"] == "ok" and P["open"] is True and P["ondemand"]["status"] == "done"
        out = cur.execute("select o.kind, o.email, o.slug from ondemand_outbox(50) o join research_requests r on r.id = o.id where r.firm_id = %s", (fid,)).fetchall()
        assert out == [("ready", "test@example.com", slug)]
        conn.rollback()


def test_partial_firm_and_refund():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("insert into research_queue (registry_id, name, priority, status) values ('zz-od2', 'Zz Partial', 5, 'submitted')")
        fid = cur.execute("select id from firms where registry_id = 'zz-od2'").fetchone()[0]
        cur.execute("update firms set slug = 'zz-partial', indexable = true where id = %s", (fid,))   # published partial page
        cur.execute("update firm_check_rows set state = 'clear' where firm_id = %s and n <= 7", (fid,))
        a = str(uuid.uuid4())
        P = _j(cur.execute("select firm_page('zz-partial', %s, true)", (a,)).fetchone()[0])
        assert P["status"] == "ok" and P["ondemand"]["missing"] == 3
        assert cur.execute("select status, lane from research_queue where registry_id = 'zz-od2'").fetchone() == ("queued", "paid")
        bal, free0 = cur.execute("select b.id, b.free_left from check_balances b where anon_id = %s", (a,)).fetchone()
        # 24 h pass without research: refunded, page locks again, credit back, refund email queued (once an email exists)
        cur.execute("update research_requests set created_at = now() - interval '25 hours', email = 'x@example.com' where firm_id = %s", (fid,))
        assert cur.execute("select ondemand_refund_expired()").fetchone()[0] == 1
        assert cur.execute("select free_left from check_balances where id = %s", (bal,)).fetchone()[0] == free0 + 1
        assert cur.execute("select kind, amount from check_events where balance_id = %s order by id desc limit 1", (bal,)).fetchone() == ("refund_ondemand", 1)
        assert cur.execute("select status from ondemand_jobs where firm_id = %s", (fid,)).fetchone()[0] == "refunded"
        assert cur.execute("select lane from research_queue where registry_id = 'zz-od2'").fetchone()[0] == "normal"
        P = _j(cur.execute("select firm_page('zz-partial', %s, false)", (a,)).fetchone()[0])
        assert P["open"] is False and P["ondemand"]["status"] == "refunded"
        assert cur.execute("select o.kind from ondemand_outbox(50) o join research_requests r on r.id = o.id where r.firm_id = %s", (fid,)).fetchall() == [("refund",)]
        # a fully checked firm: a normal unlock, no research request
        cur.execute("update firm_check_rows set state = 'clear' where firm_id = %s", (fid,))
        cur.execute("select firm_page('zz-partial', %s, true)", (str(uuid.uuid4()),))
        assert cur.execute("select count(*) from research_requests where firm_id = %s", (fid,)).fetchone()[0] == 1
        conn.rollback()
