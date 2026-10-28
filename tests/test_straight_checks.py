"""Researcher uploads stay in the holding area. They do not fill the public check rows."""
import json
import uuid
import os

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = [pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set"), pytest.mark.skip(reason="checks are off (Alex 2026-10-28): firm_check_rows is no longer filled")]

PAYLOAD = {
    "coverage": [
        {"checklist_item": "reg.sanctions x firm", "status": "records", "query_ids": ["q1"], "record_ids": ["r1"]},
        {"checklist_item": "reg.sanctions x partner", "status": "none_found", "query_ids": ["q1"]},
        {"checklist_item": "reg.sanctions x LP", "status": "not_searched"},
        {"checklist_item": "sanctions.terrorism x firm", "status": "none_found", "query_ids": ["q2"]},  # generic web only
        {"checklist_item": "sanctions.export x firm", "status": "blocked"},
        {"checklist_item": "legal.lawsuit x firm", "status": "records", "query_ids": ["q3"], "record_ids": ["r2", "r3"]},
        {"checklist_item": "registration x firm", "status": "records", "query_ids": ["q4"], "record_ids": ["r4"]},
        {"checklist_item": "conduct.political x firm", "status": "records", "record_ids": ["r5"]},
    ],
    "search_log": [
        {"query_id": "q1", "tool": "sanctions_lists", "query": "x", "executed_at": "2026-10-20T15:00:00Z"},
        {"query_id": "q2", "tool": "grok_web_search", "query": "x", "kept_urls": ["https://news.example.com/a"]},
        {"query_id": "q3", "tool": "courtlistener", "query": "x"},
        {"query_id": "q4", "tool": "form_adv", "query": "x"},
    ],
    "records": [
        {"record_id": "r1", "field_path": "sanctions", "value": {"list": "OFAC SDN", "result": "no_match"}},
        {"record_id": "r2", "field_path": "lawsuits", "value": {"court": "S.D.N.Y.", "status": "open", "caption": "A v. Zz"}},
        {"record_id": "r3", "field_path": "lawsuits", "value": {"court": "High Court (EWHC)", "status": "closed", "caption": "B v. Zz"}},
        {"record_id": "r4", "field_path": "legal_entities", "value": {"crd": "999002", "kind": "adviser", "registration_status": "SEC registered, Approved"}},
        {"record_id": "r5", "field_path": "politicalContext", "value": {"kind": "donation", "severity": "low"}},
    ],
}
# every bot record cites its page (records without a usable source are hidden as needs_source, docs/SOURCE_TIERS.md)
for _r in PAYLOAD["records"]:
    _r["sources"] = [{"url": "https://www.courtlistener.com/docket/" + _r["record_id"] + "/"}]


def test_upload_fills_checks_and_never_downgrades():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("insert into firms (slug, name, published, launch_page, data_status, sec_crd) values ('zz-st', 'Zz Straight Capital', true, true, 'real', '999002') returning id")
        fid = cur.fetchone()[0]
        cur.execute("insert into firm_check_rows (firm_id, n, title, descr, state) select %s, n, 'T' || n, 'D', 'nc' from generate_series(1, 10) n", (fid,))
        cur.execute("update firm_check_rows set state = 'clear' where firm_id = %s and n = 5", (fid,))
        cur.execute("insert into research_queue (registry_id, name, sec_crd, priority, status) values ('zz-st', 'ZZ STRAIGHT CAPITAL LLC', '999002', 1, 'submitted')")
        cur.execute("select ensure_firm_for_registry('zz-st', false)")
        cur.execute("insert into research_submissions (registry_id, payload, valid) values ('zz-st', %s, false)", (json.dumps({"coverage": []}),))
        cur.execute("select count(*) from firm_check_rows where firm_id = %s and state <> 'nc'", (fid,))
        assert cur.fetchone()[0] == 1  # invalid upload: nothing changes
        cur.execute("insert into research_submissions (registry_id, payload, valid) values ('zz-st', %s, true)", (json.dumps(PAYLOAD),))
        cur.execute("select n, state, count_label from firm_check_rows where firm_id = %s order by n", (fid,))
        got = {n: (s, c) for n, s, c in cur.fetchall()}
        assert got[1] == ("nc", None)
        assert got[5] == ("clear", None)          # the existing row is not touched
        assert got[6] == ("nc", None) and got[8] == ("nc", None) and got[10] == ("nc", None)
        cur.execute("select count(*) from research_submissions where registry_id = 'zz-st' and payload = %s::jsonb", (json.dumps(PAYLOAD),))
        assert cur.fetchone()[0] == 1           # the upload itself is untouched
        cur.execute("select firm_check_status('zz-st')")
        s = cur.fetchone()[0]; s = s if isinstance(s, dict) else json.loads(s)
        assert s["queue"] == "submitted" and s["started_at"] is None
        conn.rollback()


def test_check_findings_itemize_exactly_the_counted_records():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("insert into firms (slug, name, published, launch_page, data_status, sec_crd) values ('zz-ct', 'Zz Table Capital', true, true, 'real', '999003') returning id")
        fid = cur.fetchone()[0]
        cur.execute("insert into firm_check_rows (firm_id, n, title, descr, state) select %s, n, 'T' || n, 'D', 'nc' from generate_series(1, 10) n", (fid,))
        cur.execute("insert into research_queue (registry_id, name, sec_crd, priority, status) values ('zz-ct', 'ZZ TABLE CAPITAL LLC', '999003', 1, 'submitted')")
        cur.execute("select ensure_firm_for_registry('zz-ct', false)")
        cur.execute("insert into research_submissions (registry_id, payload, valid) values ('zz-ct', %s, true) returning id", (json.dumps(PAYLOAD),))
        sid = cur.fetchone()[0]
        cur.execute("select k, title, status from check_findings(%s) order by k", (sid,))
        rows = cur.fetchall()
        assert rows == [(6, "A v. Zz", "open"), (7, "B v. Zz", "closed"), (10, None, None)]  # no_match screen not itemized
        anon = str(uuid.uuid4())
        cur.execute("select firm_page('zz-ct', %s, false)", (anon,))
        P = cur.fetchone()[0]; P = P if isinstance(P, dict) else json.loads(P)
        # locked (blur A): only the check names; no results, counts, dates, sections or outline
        assert P["status"] == "ok" and not P["open"] and P["sections"] == [] and P["outline"] is None and P["details"] is None
        assert [set(k for k, v in c.items() if v is not None) for c in P["checks"]] == [{"n", "title", "descr"}] * 10
        cur.execute("select firm_check_status('zz-ct')")
        S = cur.fetchone()[0]; S = S if isinstance(S, dict) else json.loads(S)
        assert "checks" not in S and S["total"] == 10
        cur.execute("select firm_page('zz-ct', %s, true)", (anon,))  # a free check opens it
        P = cur.fetchone()[0]; P = P if isinstance(P, dict) else json.loads(P)
        c6 = next(c for c in P["checks"] if c["n"] == 6)
        assert P["open"] and c6["itemized"] == 0 and c6["items"] == [] and c6["state"] == "nc"
        conn.rollback()
