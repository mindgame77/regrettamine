"""A9.6: _firm_activity funds_sec counts real fund rows with a sec.gov source (not ADV summary rows); list only after a credit."""
import os

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
def test_funds_sec_count_and_list():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("""insert into firms (slug, name, published, data_status, indexable)
                       values ('zz-fsec', 'ZZ Fsec', true, 'real', true) returning id""")
        fid = cur.fetchone()[0]

        def act(open_):
            cur.execute("select _firm_activity(%s, %s)", (fid, open_))
            return cur.fetchone()[0]

        assert act(True)["funds_sec"] == {"n": 0, "items": []}
        rows = [
            ("ZZ Fund I", 100000000, "2025-01-02", "https://www.sec.gov/Archives/a", None, "real"),
            ("ZZ Fund II", None, None, None, "{https://news.example/x,https://reports.adviserinfo.sec.gov/r.pdf}", "real"),
            ("ZZ News Fund", 5, "2026-01-01", "https://news.example/y", None, "real"),
            ("ZZ Sample Fund", 1, None, "https://www.sec.gov/Archives/d", None, "needs_proof"),
            ("ZZ Fake", 1, None, "https://evilsec.gov.example/x", None, "real"),
        ]
        for name, amt, d, url, srcs, st in rows:
            cur.execute("""insert into funds (firm_id, name, raised_usd, closed_on, filing_url, source_urls, data_status)
                           values (%s, %s, %s, %s, %s, %s::text[], %s)""", (fid, name, amt, d, url, srcs, st))
        # Fix 1: heading labels can no longer be stored as fund rows at all.
        for name in ("Funds", "Regulatory AUM"):
            with pytest.raises(psycopg.errors.CheckViolation):
                with conn.transaction():
                    cur.execute("insert into funds (firm_id, name, filing_url, data_status) values (%s, %s, %s, 'real')",
                                (fid, name, "https://www.sec.gov/Archives/b"))
        a = act(True)["funds_sec"]
        assert a["n"] == 2
        assert [x["name"] for x in a["items"]] == ["ZZ Fund I", "ZZ Fund II"]
        assert a["items"][0]["url"] == "https://www.sec.gov/Archives/a" and float(a["items"][0]["raised_usd"]) == 100000000
        assert a["items"][1]["url"] == "https://reports.adviserinfo.sec.gov/r.pdf"
        locked = act(False)["funds_sec"]
        assert locked["n"] == 2 and locked["items"] is None
        conn.rollback()
