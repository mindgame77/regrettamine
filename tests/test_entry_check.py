"""Entry check, Layer 1 (A4.6, A4.7; Alex 2026-10-28): every upload into bots.research_submissions gets
'Accepted' or 'Rejected: <reason>' from instant database checks. Internal only, kept 30 days.
Each test runs in a rolled-back transaction."""
import json
import os

import pytest

DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()


@pytest.fixture()
def cur():
    if not DATABASE_URL:
        pytest.skip("DATABASE_URL is not set")
    import psycopg
    with psycopg.connect(DATABASE_URL) as c:
        if c.execute("select to_regprocedure('public._entry_check(bigint,text,text,jsonb)')").fetchone()[0] is None:
            pytest.skip("entry check migration not applied")
        try:
            yield c
        finally:
            c.rollback()


def rec(url="https://www.sec.gov/Archives/edgar/data/1/x.htm", tier="T1", field="hq", value="Los Angeles",
        as_of="2025-12-31", published_at="2026-02-25"):
    src = {"tier": tier, "published_at": published_at}
    if url is not None:
        src["url"] = url
    return {"field_path": field, "value": value, "as_of": as_of, "sources": [src]}


def payload(*records, domain="examplevc.com"):
    return {"firm": {"name": "Example VC", "primary_domain": domain}, "records": list(records)}


def check(c, p, registry="vc-test-entry-1"):
    return c.execute("select public._entry_check(null, %s, 'test-bot', %s::jsonb)",
                     (registry, json.dumps(p))).fetchone()[0]


def test_good_upload_accepted(cur):
    assert check(cur, payload(rec())) == "Accepted"
    p = payload(rec())
    p["firm"]["website"] = "https://examplevc.com"  # reused helper adds the website item (firm site, level 2)
    assert check(cur, p) == "Accepted"


def test_1_link_missing_or_malformed(cur):
    assert "no source link" in check(cur, payload(rec(url=None)))
    assert "source link is not a valid http(s) URL" in check(cur, payload(rec(url="ftp://sec.gov/x")))
    assert "source link is not a valid http(s) URL" in check(cur, payload(rec(url="sec.gov/x")))
    assert "source link is a search or chat page" in check(cur, payload(rec(url="https://www.google.com/search?q=x")))


def test_2_source_level(cur):
    assert "source level 4 is not 1 to 3" in check(cur, payload(rec(tier="T4")))
    assert "no source level" in check(cur, payload(rec(tier="")))
    assert check(cur, payload(rec(tier="T3"))) == "Accepted"


def test_3_duplicate_inside_upload(cur):
    assert "duplicate items inside the upload" in check(cur, payload(rec(), rec()))


def test_3_duplicate_of_earlier_upload(cur):
    p = payload(rec())
    cur.execute("alter table bots.research_submissions disable trigger user")
    cur.execute("alter table bots.research_submissions enable trigger aa_entry_check")
    cur.execute("insert into bots.research_submissions(registry_id, bot_id, payload) values (%s, 'test-bot', %s::jsonb)",
                ("vc-test-entry-1", json.dumps(p)))
    assert "duplicate of an earlier upload" in check(cur, p)


def norm(c, d):
    return c.execute("select public._entry_norm_date(%s)", (d,)).fetchone()[0]


def test_4_dates_normalized_not_rejected(cur):
    assert norm(cur, "Oct 5, 2026") == "2026-10-05"
    assert norm(cur, "10/05/2026") == "2026-10-05"
    assert norm(cur, "5 October 2026") == "2026-10-05"
    assert norm(cur, "2026-10-05T12:30:00Z") == "2026-10-05"
    assert norm(cur, "October 2026") == "2026-10"
    assert norm(cur, "2026-1") == "2026-01"
    assert norm(cur, "2026") == "2026"
    assert norm(cur, "2025-02-30") is None
    assert norm(cur, "soon") is None
    assert check(cur, payload(rec(as_of="12/31/2025"))) == "Accepted"
    assert check(cur, payload(rec(field="lawsuits", value={"filed_at": "March-ish 2024"}))) == "Accepted"


def fix(c, p):
    return c.execute("select public._entry_fix_payload(%s::jsonb)", (json.dumps(p),)).fetchone()[0]


def test_4_fix_payload_dates(cur):
    out = fix(cur, payload(rec(as_of="Oct 5, 2026", published_at="not a date"),
                           rec(field="lawsuits", value={"filed_at": "5 October 2026", "date": "??"})))
    r0, r1 = out["payload"]["records"]
    assert r0["as_of"] == "2026-10-05" and r0["sources"][0]["published_at"] is None
    assert r1["value"]["filed_at"] == "2026-10-05" and r1["value"]["date"] is None
    assert out["notes"] == ["2 dates unreadable, cleared"]


def test_5_status_words(cur):
    ok = rec(field="lawsuits", value={"title": "X v. Y", "status": "Settled", "side": "Defendant", "about": "Fraud"})
    assert check(cur, payload(ok)) == "Accepted"
    bad = rec(field="lawsuits", value={"title": "X v. Y", "status": "Pending"})
    assert "status word not on the fixed list" in check(cur, payload(bad))
    assert "side word not on the fixed list" in check(cur, payload(rec(field="lawsuits", value={"side": "Witness"})))
    # 'status' on other lists (e.g. people) is not a legal status word
    assert check(cur, payload(rec(field="people", value={"name": "A", "status": "current"}))) == "Accepted"


def test_6_a9_limits_archive_extras(cur):
    people = [rec(url=f"https://examplevc.com/team/{i}", tier="T2", field="people", value={"name": f"P{i}"})
              for i in range(23)]
    assert check(cur, payload(*people)) == "Accepted"
    out = fix(cur, payload(*people))
    flags = [r.get("archived") for r in out["payload"]["records"]]
    assert flags[:20] == [None] * 20 and flags[20:] == [True] * 3
    assert out["notes"] == ["3 items over the A9 limit archived"]
    thesis = rec(url="https://examplevc.com/about", tier="T2", field="thesis", value="x" * 1001)
    assert "thesis over 1,000 characters (A9.19)" in check(cur, payload(thesis))


def test_7_no_news_from_firm_site(cur):
    own = rec(url="https://blog.examplevc.com/post", tier="T2", field="press", value={"headline": "We raised"})
    assert "news item from the firm's own website or blog" in check(cur, payload(own))
    other = rec(url="https://techcrunch.com/2026/01/01/examplevc", tier="T3", field="press", value={"headline": "H"})
    assert "own website" not in check(cur, payload(other))


def test_trigger_sets_result_and_link_flag(cur):
    cur.execute("alter table bots.research_submissions disable trigger user")
    cur.execute("alter table bots.research_submissions enable trigger aa_entry_check")
    row = cur.execute("insert into bots.research_submissions(registry_id, bot_id, payload) values "
                      "('vc-test-entry-2', 'test-bot', %s::jsonb) returning entry_check, entry_check_at is not null, "
                      "entry_link_open_pending", (json.dumps(payload(rec(url=None))),)).fetchone()
    assert row[0].startswith("Rejected: no source link") and row[1] and row[2] is False
    row = cur.execute("insert into bots.research_submissions(registry_id, bot_id, payload) values "
                      "('vc-test-entry-3', 'test-bot', %s::jsonb) returning entry_check, entry_link_open_pending",
                      (json.dumps(payload(rec(value="Other"))),)).fetchone()
    assert row == ("Accepted", True)
    bad_date = rec(value="Third", as_of="sometime")
    row = cur.execute("insert into bots.research_submissions(registry_id, bot_id, payload) values "
                      "('vc-test-entry-5', 'test-bot', %s::jsonb) returning entry_check, entry_notes, payload",
                      (json.dumps(payload(bad_date)),)).fetchone()
    assert row[0] == "Accepted" and row[1] == ["1 date unreadable, cleared"]
    assert row[2]["records"][0]["as_of"] is None


def test_purge_after_30_days(cur):
    cur.execute("alter table bots.research_submissions disable trigger user")
    rid = cur.execute("insert into bots.research_submissions(registry_id, bot_id, payload, entry_check, entry_check_at) "
                      "values ('vc-test-entry-4', 'test-bot', '{}'::jsonb, 'Accepted', now() - interval '31 days') "
                      "returning id").fetchone()[0]
    assert cur.execute("select bots.entry_check_purge()").fetchone()[0] >= 1
    assert cur.execute("select entry_check from bots.research_submissions where id = %s", (rid,)).fetchone()[0] is None


def test_server_only_grants(cur):
    for fn in ("public._entry_check(bigint,text,text,jsonb)", "public._entry_fix_payload(jsonb)", "public._entry_duplicate(bigint,text,text,jsonb)",
               "bots.entry_check_purge()", "bots.entry_check_trg()"):
        for role in ("anon", "authenticated"):
            assert not cur.execute("select has_function_privilege(%s, %s, 'execute')", (role, fn)).fetchone()[0], (role, fn)
        cfg = cur.execute("select proconfig from pg_proc where oid = %s::regprocedure", (fn,)).fetchone()[0]
        assert any(c.startswith("search_path=") for c in (cfg or [])), fn
