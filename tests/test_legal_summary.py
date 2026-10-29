"""Legal case summary (Alex 2026-10-29): trim at 300, reject only with no source link, closed not rewritten, history kept."""
import os

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
URL = "https://www.courtlistener.com/docket/1/x/"


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
def test_summary_rules():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("""insert into firms (slug, name, published, data_status, indexable)
                       values ('zz-lsum', 'ZZ Lsum', true, 'real', true) returning id""")
        fid = cur.fetchone()[0]

        def case(state):
            cur.execute("insert into firm_legal_items (firm_id, grp, title, state) values (%s, 'case', %s, %s) returning id",
                        (fid, 'ZZ v. ' + state, state))
            return cur.fetchone()[0]

        def get(i):
            cur.execute("select summary, summary_date, summary_source_url, summary_by from firm_legal_items where id = %s", (i,))
            return cur.fetchone()

        def put(i, text, url, by="enricher"):
            cur.execute("select legal_summary_set(%s, %s, '2026-10-29', %s, %s)", (i, text, url, by))
            return cur.fetchone()[0]

        a = case("Active")
        assert put(a, "x", None) == {"ok": False, "reason": "no source link"}
        assert get(a)[0] is None
        r = put(a, "  " + "y" * 400, URL)
        assert r["ok"] and r["trimmed"]
        assert len(get(a)[0]) <= 300 and get(a)[3] == "enricher"
        assert put(a, "new ruling", URL)["replaced"] is True
        assert get(a)[0] == "new ruling"
        cur.execute("select count(*) from firm_legal_summary_history where legal_item_id = %s", (a,))
        assert cur.fetchone()[0] == 1
        assert put(a, "x", URL, "checker")["reason"] == "unknown writer"

        c = case("Closed")
        assert put(c, "first summary", URL)["ok"]  # an existing case can get its first summary
        assert put(c, "rewrite", URL) == {"ok": False, "reason": "closed case is not rewritten"}
        cur.execute("update firm_legal_items set summary = 'direct' where id = %s", (c,))
        assert get(c)[0] == "first summary"  # the trigger also keeps it

        # direct insert (ingest): long text trimmed, missing link drops the summary but keeps the case
        cur.execute("""insert into firm_legal_items (firm_id, grp, title, state, summary, summary_source_url, summary_by)
                       values (%s, 'case', 'ZZ ins', 'Active', %s, %s, 'research') returning summary, summary_date""", (fid, "z" * 400, URL))
        s, d = cur.fetchone()
        assert len(s) == 300 and d is not None
        cur.execute("""insert into firm_legal_items (firm_id, grp, title, state, summary)
                       values (%s, 'case', 'ZZ nolink', 'Active', 'text') returning id, summary""", (fid,))
        row = cur.fetchone()
        assert row[0] and row[1] is None

        cur.execute("select _sec_items('legal', %s)", (fid,))
        items = cur.fetchone()[0]
        assert items == [] or all("summary_url" in it for it in items)
        conn.rollback()
