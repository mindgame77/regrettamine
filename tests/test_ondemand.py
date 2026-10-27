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
    "firm": {"generated_at": "2026-10-25T00:38:26Z"},
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
        cur.execute("select ensure_firm_for_registry('zz-od1', false)")
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
        # nothing requested is waiting: toxy-researcher-3 gets nothing (never normal-lane work)
        assert cur.execute("select count(*) from research_claim('toxy-researcher-3', 5)").fetchone()[0] == 0
        info = _j(cur.execute("select ondemand_job_info(array['zz-od1'])").fetchone()[0])["zz-od1"]
        assert info["paid"] and info["requesters"] == 2 and len(info["missing_checks"]) == 10
        assert _j(cur.execute("select firm_page(%s, %s, false)", (slug, a2)).fetchone()[0])["ondemand"]["status"] == "in_progress"
        # valid research -> done, back to normal lane, both keep the page, email queued for the one with an email
        cur.execute("insert into research_submissions (registry_id, bot_id, payload, valid) values ('zz-od1', 'toxy-researcher-3', %s, true)", (json.dumps(PAYLOAD),))
        stored = _j(cur.execute("select payload from research_submissions where registry_id = 'zz-od1'").fetchone()[0])
        assert stored["firm"]["generated_at"] == "2026-10-25T00:38:26Z"
        assert cur.execute("select report_date from firms where id = %s", (fid,)).fetchone()[0] is None
        assert cur.execute("select status from ondemand_jobs where firm_id = %s", (fid,)).fetchone()[0] == "done"
        assert cur.execute("select lane from research_queue where registry_id = 'zz-od1'").fetchone()[0] == "normal"
        cur.execute("select ensure_firm_for_registry('zz-od1', false)")
        assert cur.execute("select indexable from firms where id = %s", (fid,)).fetchone()[0] is False
        assert cur.execute("select report_date from firms where id = %s", (fid,)).fetchone()[0] is None
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
        cur.execute("select ensure_firm_for_registry('zz-od2', false)")
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
        # a fully checked firm: a normal unlock with no email creates no research request
        cur.execute("update firm_check_rows set state = 'clear' where firm_id = %s", (fid,))
        cur.execute("select firm_page('zz-partial', %s, true)", (str(uuid.uuid4()),))
        assert cur.execute("select count(*) from research_requests where firm_id = %s", (fid,)).fetchone()[0] == 1
        # the same unlock with an email still saves it and queues the ready mail, even though research is done
        a2 = str(uuid.uuid4())
        P = _j(cur.execute("select firm_page('zz-partial', %s, true, 'Done@Example.com')", (a2,)).fetchone()[0])
        assert P["open"] is True
        assert cur.execute("select o.kind, o.email from ondemand_outbox(50) o join research_requests r on r.id = o.id where r.firm_id = %s and r.anon_id = %s", (fid, a2)).fetchone() == ("ready", "done@example.com")
        conn.rollback()


def test_firm_request_lane():
    """'Request this firm' files a request-lane row right away; only toxy-researcher-3 claims it, after paid checks."""
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        a = str(uuid.uuid4())
        assert _j(cur.execute("select request_firm('Zz Wombatish Requested Capital', 'zz-req@example.com', null, %s)", (a,)).fetchone()[0])["status"] == "ok"
        rid = cur.execute("select 'req-' || id from firm_requests where name_key = _queue_name_key('Zz Wombatish Requested Capital')").fetchone()[0]
        assert cur.execute("select lane, status from research_queue where registry_id = %s", (rid,)).fetchone() == ("request", "queued")
        assert cur.execute("select count(*) from firms where registry_id = %s", (rid,)).fetchone()[0] == 0
        cur.execute("insert into research_queue (registry_id, name, priority, status) values ('zz-rp1', 'Zz Paidcheck Partners', 900000, 'queued')")
        cur.execute("select ensure_firm_for_registry('zz-rp1', false)")
        fid = cur.execute("select id from firms where registry_id = 'zz-rp1'").fetchone()[0]
        cur.execute("select _ondemand_enqueue(%s, 'zz-rp1', null, 'spend_free', null, %s)", (fid, a))
        assert rid not in [r[0] for r in cur.execute("select registry_id from research_claim('toxy-researcher-1', 300)").fetchall()]
        claims = [[r[0] for r in cur.execute("select registry_id from research_claim('toxy-researcher-3', 5)").fetchall()] for _ in range(3)]
        assert claims == [["zz-rp1"], [rid], []]
        cur.execute("select research_submit(%s, 'toxy-researcher-3', %s, 1, true, '[]'::jsonb)", (rid, json.dumps(PAYLOAD)))
        assert cur.execute("select status from firm_requests where 'req-' || id = %s", (rid,)).fetchone()[0] == "linked"
        assert cur.execute("select lane from research_queue where registry_id = %s", (rid,)).fetchone()[0] == "normal"
        conn.rollback()


def test_notify_signup_job_and_single_ready_mail():
    """Notify-me on a known firm files a paid job; an unknown name files req-<id> in lane request.
    The ready email is the research_requests row, once, and not the ready_request template."""
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("insert into research_queue (registry_id, name, priority, status) values ('zz-nf1', 'Zz Notify Partners', 900000, 'queued')")
        cur.execute("select ensure_firm_for_registry('zz-nf1', false)")
        fid, slug = cur.execute("select id, slug from firms where registry_id = 'zz-nf1'").fetchone()
        a = str(uuid.uuid4())
        assert _j(cur.execute("select notify_when_checked(%s, 'Notify@Example.com', %s)", (slug, a)).fetchone()[0])["status"] == "ok"
        assert cur.execute("select lane from research_queue where registry_id = 'zz-nf1'").fetchone()[0] == "paid"
        kind, fr = cur.execute("select spend_kind, firm_request_id from research_requests where firm_id = %s", (fid,)).fetchone()
        assert kind == "request" and fr is None
        linked, notified = cur.execute(
            "select research_request_id is not null, notified_at is not null from check_requests where firm_id = %s", (fid,)).fetchone()
        assert linked and notified
        assert cur.execute("select count(*) from ondemand_outbox(50) o join research_requests r on r.id = o.id where r.firm_id = %s", (fid,)).fetchone()[0] == 0
        cur.execute("update ondemand_jobs set status = 'done', done_at = now() where firm_id = %s", (fid,))
        cur.execute("update research_requests set status = 'done', done_at = now() where firm_id = %s", (fid,))
        assert cur.execute(
            "select o.kind, o.email from ondemand_outbox(50) o join research_requests r on r.id = o.id where r.firm_id = %s", (fid,)
        ).fetchone() == ("ready", "notify@example.com")
        assert cur.execute("select count(*) from ready_check_requests() where slug = %s", (slug,)).fetchone()[0] == 0
        b = str(uuid.uuid4())
        cur.execute("select request_check('zz brand new capital', 'new@example.com', %s)", (b,))
        reg, lane, src = cur.execute(
            "select registry_id, lane, list_source from research_queue where list_source = 'check_request' and lower(name) = 'zz brand new capital'"
        ).fetchone()
        assert reg.startswith("req-") and lane == "request" and src == "check_request"
        conn.rollback()


def test_spend_without_email_unlocks_and_still_starts_research():
    """A signed-out spend with no address unlocks the page. An unfinished firm still gets a paid job.
    An address, when one is given, is stored for the ready email. A finished firm stores nothing extra."""
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("insert into research_queue (registry_id, name, priority, status) values ('zz-noem', 'Zz Noemail Partners', 900000, 'submitted')")
        cur.execute("select ensure_firm_for_registry('zz-noem', false)")
        fid, slug = cur.execute("select id, slug from firms where registry_id = 'zz-noem'").fetchone()
        cur.execute("update firms set indexable = true where id = %s", (fid,))
        cur.execute("update firm_check_rows set state = 'clear' where firm_id = %s and n <= 7", (fid,))
        a = str(uuid.uuid4())
        P = _j(cur.execute("select firm_page(%s, %s, true, null)", (slug, a)).fetchone()[0])
        assert P["status"] == "ok" and P["open"] is True and P["ondemand"]["status"] == "queued"
        job, email = cur.execute("select j.status, r.email from ondemand_jobs j join research_requests r on r.job_id = j.id where j.firm_id = %s", (fid,)).fetchone()
        assert job == "queued" and email is None
        assert cur.execute("select lane from research_queue where registry_id = 'zz-noem'").fetchone()[0] == "paid"
        b = str(uuid.uuid4())
        P = _j(cur.execute("select firm_page(%s, %s, true, 'Later@Example.com')", (slug, b)).fetchone()[0])
        assert P["open"] is True
        assert cur.execute("select count(*) from ondemand_jobs where firm_id = %s", (fid,)).fetchone()[0] == 1
        assert cur.execute("select email from research_requests where firm_id = %s and anon_id = %s", (fid, b)).fetchone()[0] == "later@example.com"
        cur.execute("insert into research_queue (registry_id, name, priority, status) values ('zz-done2', 'Zz Done Partners', 900000, 'submitted')")
        cur.execute("select ensure_firm_for_registry('zz-done2', false)")
        fid2, slug2 = cur.execute("select id, slug from firms where registry_id = 'zz-done2'").fetchone()
        cur.execute("update firms set indexable = true where id = %s", (fid2,))
        cur.execute("update firm_check_rows set state = 'clear' where firm_id = %s", (fid2,))
        c = str(uuid.uuid4())
        P = _j(cur.execute("select firm_page(%s, %s, true, null)", (slug2, c)).fetchone()[0])
        assert P["status"] == "ok" and P["open"] is True and P["ondemand"] is None
        assert cur.execute("select count(*) from research_requests where firm_id = %s", (fid2,)).fetchone()[0] == 0
        conn.rollback()


def test_paid_job_preempts_normal_claim_and_keeps_the_upload():
    """A fresh normal-lane claim (gap-fill) loses the firm as soon as a paid job exists.
    Researcher 3 can claim it. The previous bot's later submit is stored unchanged.
    A normal claim with no paid or request job still lasts until the 6-hour expiry."""
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("insert into research_queue (registry_id, name, priority, status, lane, claimed_by, claimed_at, last_error) values "
                    "('zz-pre1', 'Zz Preempt Partners', 900000, 'claimed', 'normal', 'portal-night-bot', now(), 'gap-fill claim'), "
                    "('zz-hold', 'Zz Still Held', 900000, 'claimed', 'normal', 'portal-night-bot', now() - interval '1 hour', 'gap-fill claim'), "
                    "('zz-old', 'Zz Expired Hold', 900000, 'claimed', 'normal', 'portal-night-bot', now() - interval '7 hours', 'gap-fill claim'), "
                    "('zz-reqhold', 'Zz Request Held', 0, 'claimed', 'request', 'portal-night-bot', now(), 'gap-fill claim')")
        cur.execute("select ensure_firm_for_registry('zz-pre1', false)")
        fid = cur.execute("select id from firms where registry_id = 'zz-pre1'").fetchone()[0]
        a = str(uuid.uuid4())
        cur.execute("select _ondemand_enqueue(%s, 'zz-pre1', null, 'spend_free', null, %s)", (fid, a))
        status, lane, claimed_by, prior = cur.execute(
            "select status, lane, claimed_by, prior_claimed_by from research_queue where registry_id = 'zz-pre1'").fetchone()
        assert (status, lane, claimed_by, prior) == ("queued", "paid", None, "portal-night-bot")
        # the young normal claim is not released; the 6-hour claim is, on the next claim call
        assert cur.execute("select status, claimed_by from research_queue where registry_id = 'zz-hold'").fetchone() == ("claimed", "portal-night-bot")
        assert [r[0] for r in cur.execute("select registry_id from research_claim('toxy-researcher-3', 1)").fetchall()] == ["zz-pre1"]
        assert cur.execute("select status, claimed_by from research_queue where registry_id = 'zz-hold'").fetchone() == ("claimed", "portal-night-bot")
        assert cur.execute("select status, claimed_by, left(last_error, 13) from research_queue where registry_id = 'zz-old'").fetchone() == (
            "queued", None, "claim expired")
        # a stranger is still rejected; the preempted bot's dump is stored as sent and does not drop researcher 3
        denied = _j(cur.execute("select research_submit('zz-pre1', 'toxy-researcher-1', %s, 1, true, '[]'::jsonb)", (json.dumps(PAYLOAD),)).fetchone()[0])
        assert denied["ok"] is False and "not claimed" in denied["error"]
        dump = {"firm": {"generated_at": "2026-10-25T00:38:26Z", "note": "friend dump"}, "records": []}
        raw = json.dumps(dump)
        ok = _j(cur.execute("select research_submit('zz-pre1', 'portal-night-bot', %s::jsonb, 1, true, '[]'::jsonb)", (raw,)).fetchone()[0])
        assert ok["ok"] is True and ok["status"] == "submitted"
        stored = cur.execute("select payload::text from research_submissions where id = %s", (ok["submission_id"],)).fetchone()[0]
        assert json.loads(stored) == dump
        assert cur.execute("select status, claimed_by, lane from research_queue where registry_id = 'zz-pre1'").fetchone() == (
            "claimed", "toxy-researcher-3", "normal")
        # request lane: a normal bot's hold is released and researcher 3 can take it
        cur.execute("select _preempt_normal_claims()")
        assert cur.execute("select status, lane, claimed_by, prior_claimed_by from research_queue where registry_id = 'zz-reqhold'").fetchone() == (
            "queued", "request", None, "portal-night-bot")
        assert [r[0] for r in cur.execute("select registry_id from research_claim('toxy-researcher-1', 50)").fetchall()].count("zz-reqhold") == 0
        assert cur.execute("select registry_id from research_claim('toxy-researcher-3', 1)").fetchone()[0] == "zz-reqhold"
        # before anyone reclaims, the preempted bot's valid submit is the normal submitted path
        cur.execute("update research_queue set status = 'queued', claimed_by = null, lane = 'paid' where registry_id = 'zz-reqhold'")
        cur.execute("insert into ondemand_jobs (firm_id, registry_id, status) values (%s, 'zz-reqhold', 'queued')", (fid,))
        early = _j(cur.execute("select research_submit('zz-reqhold', 'portal-night-bot', %s::jsonb, 1, true, '[]'::jsonb)", (raw,)).fetchone()[0])
        assert early["ok"] is True and early["status"] == "submitted"
        assert json.loads(cur.execute("select payload::text from research_submissions where id = %s", (early["submission_id"],)).fetchone()[0]) == dump
        assert cur.execute("select status from research_queue where registry_id = 'zz-reqhold'").fetchone()[0] == "submitted"
        assert cur.execute("select status from ondemand_jobs where registry_id = 'zz-reqhold'").fetchone()[0] == "done"
        conn.rollback()
