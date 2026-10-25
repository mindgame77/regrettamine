"""Header fields, searched-at fallback and filed years are read-time only. Raw rows stay put."""
import json
import os
import uuid

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")


def _j(cur, sql, args=()):
    cur.execute(sql, args)
    row = cur.fetchone()[0]
    return row if isinstance(row, dict) else json.loads(row)


def test_header_website_assets_and_report_date_are_display_only():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute(
            """insert into firms (slug, name, display_name, legal_name, published, data_status, sec_crd, report_date, aum_display)
               values ('zz-hdr', 'ZZ Header Ventures', 'ZZ Header Ventures', 'ZZ HEADER VENTURES LLC', true, 'real', '999441', '2026-10-02', '106.5')
               returning id"""
        )
        fid = cur.fetchone()[0]
        cur.execute(
            """insert into research_queue (registry_id, name, sec_crd, priority, status, hq_city, state, country, website)
               values ('zz-hdr', 'ZZ HEADER VENTURES LLC', '999441', 1, 'submitted', 'LOS ANGELES', 'California', 'US', 'https://www.instagram.com/zzhdr/')"""
        )
        cur.execute(
            """insert into firm_profile_facts (firm_id, section, label, value, sort_order)
               values (%s, 'overview', 'Overview', 'Item 5F regulatory AUM $3,383,647,755. Seen at https://zz-hdr-upfront.com/.', 1)
               returning id""",
            (fid,),
        )
        fact = cur.fetchone()[0]
        cur.execute(
            "insert into firm_profile_facts (firm_id, section, label, value, sort_order) values (%s, 'funds', 'Funds', 'Schedule D gross assets $9,000,000,000', 2)",
            (fid,),
        )
        cur.execute("insert into sources (url, retrieved_at, data_status) values ('https://zz-hdr-upfront.com/', now(), 'real') on conflict (url) do update set url = excluded.url returning id")
        sid = cur.fetchone()[0]
        cur.execute("insert into sources (url, retrieved_at, data_status) values ('https://www.sec.gov/zz-hdr-firm', now(), 'real') on conflict (url) do update set url = excluded.url returning id")
        sec = cur.fetchone()[0]
        cur.execute(
            """insert into fact_sources (source_id, firm_id, fact_type, fact_id, label, sort_order, data_status)
               values (%s, %s, 'firm_profile_facts', %s, 'upfront.com', 0, 'real'), (%s, %s, 'firm_profile_facts', %s, 'sec.gov', 1, 'real')""",
            (sid, fid, fact, sec, fid, fact),
        )
        cur.execute(
            "insert into firm_check_rows (firm_id, n, title, descr, state) select %s, n, 'T' || n, 'D', case when n = 1 then 'clear' else 'nc' end from generate_series(1, 10) n",
            (fid,),
        )
        anon = str(uuid.uuid4())
        P = _j(cur, "select firm_page('zz-hdr', %s, true)", (anon,))
        assert P["open"] is True
        assert P["firm"]["name"] == "ZZ Header Ventures"
        assert P["firm"]["sec_name"] == "ZZ HEADER VENTURES LLC"
        assert P["firm"]["hq"] == "Los Angeles, CA"
        assert P["firm"]["website"] == "https://zz-hdr-upfront.com/"
        assert P["firm"]["assets"] == "$3,383,647,755"
        assert P["hero"] == []
        c1 = next(c for c in P["checks"] if c["n"] == 1)
        c2 = next(c for c in P["checks"] if c["n"] == 2)
        assert c1["searched_at"].startswith("2026-10-02")
        assert c2["searched_at"] is None
        cur.execute("select value from firm_profile_facts where id = %s", (fact,))
        assert "Item 5F" in cur.fetchone()[0]
        cur.execute("select website from research_queue where registry_id = 'zz-hdr'")
        assert cur.fetchone()[0] == "https://www.instagram.com/zzhdr/"
        cur.execute("select aum_display, report_date::text from firms where id = %s", (fid,))
        assert cur.fetchone() == ("106.5", "2026-10-02")

        cur.execute("update firms set primary_domain = 'example.com', hq = 'Menlo Park, CA' where id = %s", (fid,))
        cur.execute("update firms set aum_display = '$106.5B' where id = %s", (fid,))
        cur.execute("delete from firm_profile_facts where firm_id = %s", (fid,))
        P = _j(cur, "select firm_page('zz-hdr', %s, false)", (anon,))
        assert P["firm"]["website"] == "https://example.com/"
        assert P["firm"]["hq"] == "Menlo Park, CA"
        assert P["firm"]["assets"] == "$106.5B"
        conn.rollback()


def test_check_findings_year_is_the_filed_date_only():
    import psycopg

    payload = {
        "coverage": [{"checklist_item": "legal.lawsuit x firm", "status": "records", "query_ids": ["q"], "record_ids": ["a", "b", "c"]}],
        "search_log": [{"query_id": "q", "tool": "courtlistener", "query": "x"}],
        "records": [
            {"record_id": "a", "field_path": "lawsuits", "value": {"caption": "Old v. Firm", "status": "closed", "filed_at": "2013-05-06", "date": "2054-01-01"},
             "sources": [{"url": "https://www.courtlistener.com/docket/a/"}]},
            {"record_id": "b", "field_path": "lawsuits", "value": {"caption": "Later v. Firm", "status": "open", "filed_at": "2099-01-01"},
             "sources": [{"url": "https://www.courtlistener.com/docket/b/"}]},
            {"record_id": "c", "field_path": "lawsuits", "value": {"caption": "Undated v. Firm", "status": "open", "cycle": "2054"},
             "sources": [{"url": "https://www.courtlistener.com/docket/c/"}]},
        ],
    }
    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("insert into research_queue (registry_id, name, priority, status) values ('zz-yr', 'ZZ Year Capital', 1, 'submitted')")
        cur.execute("insert into research_submissions (registry_id, payload, valid) values ('zz-yr', %s, true) returning id", (json.dumps(payload),))
        sid = cur.fetchone()[0]
        cur.execute("select title, yr from check_findings(%s) order by title", (sid,))
        got = {t: y for t, y in cur.fetchall()}
        assert got["Old v. Firm"] == "2013"
        assert got["Later v. Firm"] is None
        assert got["Undated v. Firm"] is None
        cur.execute("select payload->'records'->0->'value'->>'date' from research_submissions where id = %s", (sid,))
        assert cur.fetchone()[0] == "2054-01-01"
        conn.rollback()
