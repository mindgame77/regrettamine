"""'Not checked yet' pages: ensure_firm makes a published, noindex page with the same template.
A queue row does not. 'Check with 1 credit' buys on-demand research (tests/test_ondemand.py). A researcher upload does not make the page indexable."""
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
                 "value": {"crd": "998301", "kind": "adviser", "registration_status": "SEC registered, Approved"}}],
}


def _j(v):
    return v if isinstance(v, (dict, list)) else json.loads(v)


def test_unchecked_page_lifecycle():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("insert into firms (slug, name, published, data_status) values ('zz-quokka-capital', 'Zz Quokka Capital Checked', true, 'real')")
        cur.execute("insert into research_queue (registry_id, name, sec_crd, lei, priority, status, hq_city, state, country) values "
                    "('zz-u1', 'ZZ QUOKKA CAPITAL MANAGEMENT, LLC', '998301', 'LEI998301', 5, 'queued', 'AUSTIN', 'TX', 'US')")
        assert cur.execute("select count(*) from firms where registry_id = 'zz-u1'").fetchone()[0] == 0
        cur.execute("select ensure_firm_for_registry('zz-u1', false)")
        fid, slug, name, pub, ix = cur.execute("select id, slug, name, published, indexable from firms where registry_id = 'zz-u1'").fetchone()
        assert (slug, name, pub, ix) == ("zz-quokka-capital-2", "ZZ Quokka Capital", True, False)   # slug clash -> suffix
        assert cur.execute("select count(*), count(*) filter (where state = 'nc') from firm_check_rows where firm_id = %s", (fid,)).fetchone() == (10, 10)
        anon = str(uuid.uuid4())
        P = _j(cur.execute("select firm_page(%s, %s, false)", (slug, anon)).fetchone()[0])
        assert P["status"] == "ok" and P["open"] is False and P["unchecked"] is True and P["done"] == 0
        assert [(h["label"], h["value"]) for h in P["hero"]] == [("HQ", "Austin, TX"), ("SEC CRD", "998301"), ("LEI", "LEI998301")]
        # 'Check with 1 credit' on an unchecked page spends 1 credit and files on-demand research
        P = _j(cur.execute("select firm_page(%s, %s, true)", (slug, anon)).fetchone()[0])
        assert P["status"] == "ok" and P["ondemand"]["status"] == "queued"
        assert cur.execute("select count(*) from check_events e join firms f on f.id = e.firm_id where f.slug = %s", (slug,)).fetchone()[0] == 1
        assert cur.execute("select indexable from firm_meta(%s)", (slug,)).fetchone()[0] is False
        assert cur.execute("select count(*) from firm_sitemap(1, 10000) where slug = %s", (slug,)).fetchone()[0] == 0
        sug = [r["slug"] for r in _j(cur.execute("select firm_suggest('zz quokka')").fetchone()[0])]
        assert sug == ["zz-quokka-capital", slug]                   # findable, ranked below the checked firm
        # a researcher upload stays in the holding area and does not make the page indexable
        cur.execute("insert into research_submissions (registry_id, payload, valid) values ('zz-u1', %s, true)", (json.dumps(PAYLOAD),))
        assert cur.execute("select id, slug, indexable from firms where registry_id = 'zz-u1'").fetchone() == (fid, slug, False)
        assert cur.execute("select count(*) from firm_sitemap(1, 10000) where slug = %s", (slug,)).fetchone()[0] == 0
        cur.execute("select ensure_firm_for_registry('zz-u1', false)")
        assert cur.execute("select id, slug, indexable from firms where registry_id = 'zz-u1'").fetchone() == (fid, slug, False)
        assert cur.execute("select count(*) filter (where state = 'nc') from firm_check_rows where firm_id = %s", (fid,)).fetchone()[0] == 10
        assert cur.execute("select status from ondemand_jobs where firm_id = %s", (fid,)).fetchone()[0] == "done"
        conn.rollback()

