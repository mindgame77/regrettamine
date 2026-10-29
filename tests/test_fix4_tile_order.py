"""Fix 4 (B6d.6): AUM and Fund assets tiles read only firms.aum_*/fund_assets_* and need a Form ADV link."""
import os

import pytest

pytest.importorskip("psycopg")
import psycopg  # noqa: E402

DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
ADV = "https://reports.adviserinfo.sec.gov/reports/ADV/157373/PDF/157373.pdf"


@pytest.mark.parametrize("url,ok", [
    (ADV, True), ("https://adviserinfo.sec.gov/firm/summary/157373", True), ("https://files.adviserinfo.sec.gov/IAPD/x.pdf", True),
    ("https://www.sec.gov/Archives/edgar/data/1/0001/def14a.htm", False), ("https://www.sec.gov/news/press-release/2026-1", False),
    ("https://greenoaks.com/press-release/fund", False), ("http://adviserinfo.sec.gov/firm/summary/1", False),
    ("https://adviserinfo.sec.gov.evil.com/x", False), (None, False),
])
def test_adv_source_ok(url, ok):
    with psycopg.connect(DATABASE_URL) as c:
        assert c.execute("select public._adv_source_ok(%s)", (url,)).fetchone()[0] is ok


def test_fund_assets_still_reject_a_def14a_link():
    with psycopg.connect(DATABASE_URL) as c, c.cursor() as cur:
        cur.execute("insert into firms (slug, name, published, data_status) values ('zz-f4', 'ZZ F4', true, 'real')")
        cur.execute("update firms set aum_source_url = 'https://www.sec.gov/Archives/def14a.htm' where slug = 'zz-f4'")
        with pytest.raises(psycopg.errors.CheckViolation):
            cur.execute("update firms set fund_assets_source_url = 'https://www.sec.gov/Archives/def14a.htm' where slug = 'zz-f4'")
        c.rollback()


def test_money_tiles_only_lab_and_only_with_adv_link():
    with psycopg.connect(DATABASE_URL) as c, c.cursor() as cur:
        fid = cur.execute("insert into firms (slug, name, published, data_status, aum_amount, aum_currency, aum_source_url) "
                          "values ('zz-f4b', 'ZZ', true, 'real', 82165771068, 'USD', %s) returning id", (ADV,)).fetchone()[0]
        assert cur.execute("select public._firm_money_tiles(%s)", (fid,)).fetchone()[0] is None  # not a lab firm
        lab = cur.execute("select id from firms where public._lab_firm(id) limit 1").fetchone()
        if lab:
            cur.execute("update firms set aum_amount = 82165771068, aum_currency = 'USD', aum_source_url = %s, "
                        "fund_assets_amount = 60100000000, fund_assets_currency = 'USD', fund_assets_source_url = null where id = %s", (ADV, lab[0]))
            m = cur.execute("select public._firm_money_tiles(%s)", (lab[0],)).fetchone()[0]
            assert m["aum"]["url"] == ADV and m["aum"]["amount"] == 82165771068
            assert "fund_assets" not in m  # no Form ADV link = no tile
        c.rollback()
