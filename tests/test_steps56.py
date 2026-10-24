"""Steps 5-6: firm requests (dedupe, validation, rate limit), source tiers / allowlist, duplicate merge + slug redirects.
Everything runs in one transaction per test and is rolled back."""
import os
import uuid

import pytest

psycopg = pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")


@pytest.fixture
def cur():
    with psycopg.connect(DATABASE_URL) as c:
        with c.cursor() as k:
            yield k
        c.rollback()


def req(cur, name, email, web=None, anon=None):
    cur.execute("select request_firm(%s, %s, %s, %s)::jsonb", (name, email, web, anon or str(uuid.uuid4())))
    return cur.fetchone()[0]


def test_request_firm_dedupes_and_validates(cur):
    a = req(cur, "Zz Test Ventures", "one@example.com", "https://www.zztest.vc/about")
    assert a["status"] == "ok" and not a["already_requested"]
    b = req(cur, "ZZ TEST  ventures", "two@example.com")
    assert b["status"] == "ok"
    cur.execute("select count(*) from firm_requests where name_key = _queue_name_key('Zz Test Ventures')")
    assert cur.fetchone()[0] == 1
    cur.execute("select requesters, website_domain from firm_requests_open where name_key = _queue_name_key('Zz Test Ventures')")
    assert cur.fetchone() == (2, "zztest.vc")
    assert req(cur, "Zz Test Ventures", "one@example.com")["already_requested"] is True
    assert req(cur, "Zz Test Ventures", "not-an-email")["status"] == "bad_email"
    assert req(cur, "<b>x</b>", "a@example.com")["status"] == "bad_name"
    assert req(cur, "Zz Other", "a@example.com", "not a site")["status"] == "bad_website"


def test_request_firm_rate_limit(cur):
    anon = str(uuid.uuid4())
    res = [req(cur, f"Zz Rate Firm {c}", f"r{c}@example.com", anon=anon)["status"] for c in "abcdef"]
    assert res[:5] == ["ok"] * 5 and res[5] == "rate_limited"


def test_source_tiers(cur):
    for url, tier in [("https://find-and-update.company-information.service.gov.uk/company/1", "trusted"),
                      ("https://www.fec.gov/data/", "trusted"), ("https://sanctionssearch.ofac.treas.gov/", "trusted"),
                      ("https://www.sanctionsmap.eu/", "trusted"), ("https://www.gov.uk/government/organisations/foreign-commonwealth-development-office", "trusted"),
                      ("https://techcrunch.com/x", "other"), ("https://www.google.com/search?q=x", None), (None, None)]:
        cur.execute("select source_tier(%s)", (url,))
        assert cur.fetchone()[0] == tier, url


def test_merge_firms_redirects_and_aliases(cur):
    cur.execute("select slug, name from firms where published and deleted_at is null and not coalesce(is_test, false) order by slug limit 2")
    (keep, _), (drop, drop_name) = cur.fetchall()
    cur.execute("select merge_firms(%s, %s, 'test')", (keep, drop))
    cur.execute("select firm_redirect(%s)", (drop,))
    assert cur.fetchone()[0] == keep
    cur.execute("select deleted_at is not null, published from firms where slug = %s", (drop,))
    assert cur.fetchone() == (True, False)
    cur.execute("select count(*) from firm_aliases a join firms f on f.id = a.firm_id where f.slug = %s and lower(a.alias) = lower(%s)", (keep, drop_name))
    assert cur.fetchone()[0] == 1
    cur.execute("select firm_redirect('zz-no-such-firm-anywhere')")
    assert cur.fetchone()[0] is None
