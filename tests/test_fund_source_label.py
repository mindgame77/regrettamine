"""B6c.1/B6c.8/A1.8: latest_fund.url_label names the fund link's real source (null for sec.gov or unknown)."""
import os

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
def test_url_label():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("""insert into firms (slug, name, published, data_status, indexable)
                       values ('zz-flab', 'ZZ Flab', true, 'real', true) returning id""")
        fid = cur.fetchone()[0]
        cur.execute("insert into trusted_source_domains (domain, label, kind) values ('zztrusted.example', 'ZZ Trusted', 'regulator')")
        for pub, st in (("ZZ News", "real"), ("ZZ News", "real"), ("Other Name", "real"), ("Fake Outlet", "needs_proof")):
            cur.execute("""insert into press_items (publisher, domain, url, headline, data_status, retrieved_at)
                           values (%s, 'www.zznews.example', 'https://zznews.example/a', 'h', %s, now())""", (pub, st))

        def label(url):
            cur.execute("delete from funds where firm_id = %s", (fid,))
            cur.execute("insert into funds (firm_id, name, raised_usd, raised_currency, closed_on, filing_url, data_status) values (%s, 'ZZ F', 1, 'USD', '2026-01-01', %s, 'real')", (fid, url))
            cur.execute("select _firm_activity(%s, true)->'latest_fund'", (fid,))
            return cur.fetchone()[0].get("url_label")

        assert label("https://www.sec.gov/Archives/x") is None
        assert label("https://reports.adviserinfo.sec.gov/x") is None
        assert label("https://news.zztrusted.example/p") == "ZZ Trusted"
        assert label("https://www.zznews.example/b") == "ZZ News"
        assert label("https://unknown.example/c") is None
        assert label("https://evilsec.gov.example/c") is None
        conn.rollback()
