"""Fix 7: Headquarters has one home on the firm.

Level 1 is a SEC Form ADV page. Level 2 is the firm's own website. Level 3 is a national company
register or a trusted page. A higher level replaces the stored city, region, country, and link.
The same level replaces only when its source date is newer. A lower level is blocked. The old
Headquarters rows are not copied and not deleted. Every case below rolls back.
"""
import json
import os
from pathlib import Path

import pytest

pytest.importorskip("psycopg")
import psycopg  # noqa: E402

DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
ADV = "https://reports.adviserinfo.sec.gov/reports/ADV/157373/PDF/157373.pdf"
HOUSE = "https://find-and-update.company-information.service.gov.uk/company/OC123456"
ROOT = Path(__file__).resolve().parents[1]
MIGRATION = (ROOT / "supabase/migrations/20261029330000_fix7_headquarters.sql").read_text()


def _firm(cur, slug="zz-f7"):
    return cur.execute(
        "insert into firms (slug, name, published, data_status, primary_domain, hq) "
        "values (%s, 'ZZ F7', true, 'real', 'zz-firm.example', 'Old Town') returning id",
        (slug,),
    ).fetchone()[0]


def _item(city, country, region=""):
    return json.dumps({"label": "Headquarters", "city": city, "region": region, "country": country, "value": city})


def _place(cur, fid, city, country, url, day, region="California"):
    return cur.execute(
        "select public._place_hq(%s, %s, %s, %s, %s, %s)",
        (fid, city, region, country, url, day),
    ).fetchone()[0]


def _row(cur, fid):
    return cur.execute(
        "select hq_city, hq_region, hq_country, hq_source_url, hq_source_level, hq_source_date::text, hq "
        "from firms where id = %s",
        (fid,),
    ).fetchone()


def test_migration_copies_nothing_and_leaves_the_page_reader_alone():
    low = MIGRATION.lower()
    assert "insert into public.firms" not in low
    assert "insert into firms" not in low
    assert "delete from public.firm_profile_facts" not in low
    assert "delete from firm_profile_facts" not in low
    assert "create or replace function public.firm_page" not in low
    assert "hq_city" in MIGRATION and "_check8_outside_us" in MIGRATION


@pytest.mark.parametrize("url,level", [
    (ADV, 1),
    ("https://adviserinfo.sec.gov/firm/summary/157373", 1),
    ("https://www.sec.gov/about/forms/formadv-part2.pdf", 1),
    ("https://zz-firm.example/contact", 2),
    ("https://www.zz-firm.example/contact", 2),
    (HOUSE, 3),
    ("https://www.companieshouse.gov.uk/company/OC123456", 3),
    ("https://example.com/about", None),
    ("http://adviserinfo.sec.gov/firm/summary/1", None),
    (None, None),
])
def test_source_level(url, level):
    with psycopg.connect(DATABASE_URL) as c, c.cursor() as cur:
        fid = _firm(cur)
        got = cur.execute("select public._hq_source_level(%s, %s, null)", (fid, url)).fetchone()[0]
        assert got == level
        c.rollback()


def test_trusted_page_is_level_3():
    with psycopg.connect(DATABASE_URL) as c, c.cursor() as cur:
        fid = _firm(cur)
        cur.execute("insert into trusted_source_domains (domain, label, kind) values ('zzhq.example', 'ZZ', 'regulator')")
        assert cur.execute(
            "select public._hq_source_level(%s, %s, null)", (fid, "https://zzhq.example/office")
        ).fetchone()[0] == 3
        assert _place(cur, fid, "Austin", "US", "https://zzhq.example/office", "2024-01-01", "Texas") is None
        assert _row(cur, fid)[:6] == ("Austin", "Texas", "US", "https://zzhq.example/office", 3, "2024-01-01")
        c.rollback()


def test_each_conflict_case_rolls_back():
    """Higher replaces. Lower is blocked. The same level needs a newer date. The old HQ text stays."""
    with psycopg.connect(DATABASE_URL) as c, c.cursor() as cur:
        fid = _firm(cur)
        assert _place(cur, fid, "Palo Alto", "US", "https://zz-firm.example/contact", "2025-06-01") is None
        assert _row(cur, fid) == ("Palo Alto", "California", "US", "https://zz-firm.example/contact", 2, "2025-06-01", "Old Town")
        # Higher level replaces even when its date is older.
        assert _place(cur, fid, "Menlo Park", "US", ADV, "2020-01-01") is None
        assert _row(cur, fid)[:6] == ("Menlo Park", "California", "US", ADV, 1, "2020-01-01")
        # Lower level is refused.
        why = _place(cur, fid, "London", "GB", HOUSE, "2026-08-01", "England")
        assert "lower than the stored level 1" in why
        assert _row(cur, fid)[:4] == ("Menlo Park", "California", "US", ADV)
        # Same level, older or missing date, is refused.
        assert "not newer" in _place(cur, fid, "Cambridge", "US", ADV, "2019-01-01", "Massachusetts")
        assert "not newer" in _place(cur, fid, "Cambridge", "US", ADV, None, "Massachusetts")
        assert _row(cur, fid)[0] == "Menlo Park"
        # Same level, newer date, replaces.
        assert _place(cur, fid, "Cambridge", "US", ADV, "2026-03-01", "Massachusetts") is None
        assert _row(cur, fid)[:6] == ("Cambridge", "Massachusetts", "US", ADV, 1, "2026-03-01")
        # A country name that is not an ISO code is refused, and the stored row stays.
        assert cur.execute(
            "select public._place_hq_item(%s, %s::jsonb, %s, %s)",
            (fid, json.dumps({"city": "Paris", "country": "France"}), ADV, "2026-04-01"),
        ).fetchone()[0].startswith("no ISO country code")
        assert _row(cur, fid)[0] == "Cambridge"
        c.rollback()


def test_side_table_is_blocked_and_a_sourced_record_is_routed():
    with psycopg.connect(DATABASE_URL) as c, c.cursor() as cur:
        fid = _firm(cur)
        cur.execute(
            "insert into firm_profile_facts (firm_id, section, label, value) values (%s, 'overview', 'Headquarters', 'NYC')",
            (fid,),
        )
        assert cur.execute("select count(*) from firm_profile_facts where firm_id = %s", (fid,)).fetchone()[0] == 0
        assert _row(cur, fid)[2] is None
        reason = cur.execute(
            "select reason from money_home_blocked where firm_id = %s order by id desc limit 1", (fid,)
        ).fetchone()[0]
        assert "fix 7" in reason and "no city" in reason
        cur.execute(
            "insert into vc_source_facts (firm_id, fact_type, section, value, source_url, retrieved_at, data_status) "
            "values (%s, 'fund_fact', 'overview', %s, %s, '2024-05-01', 'real')",
            (fid, json.dumps({"field": "hq", "city": "London", "region": "England", "country": "GB"}), HOUSE),
        )
        assert cur.execute("select count(*) from vc_source_facts where firm_id = %s", (fid,)).fetchone()[0] == 0
        assert _row(cur, fid)[:6] == ("London", "England", "GB", HOUSE, 3, "2024-05-01")
        # An old Headquarters row can still be edited. A new one cannot.
        cur.execute("set local session_replication_role = replica")
        old = cur.execute(
            "insert into firm_profile_facts (firm_id, section, label, value) values (%s, 'overview', 'Headquarters', 'Old') returning id",
            (fid,),
        ).fetchone()[0]
        cur.execute("set local session_replication_role = origin")
        cur.execute("update firm_profile_facts set value = 'Kept' where id = %s", (old,))
        assert cur.execute("select value from firm_profile_facts where id = %s", (old,)).fetchone()[0] == "Kept"
        c.rollback()


def test_checker_routes_and_entry_check_refuses_a_bad_record():
    with psycopg.connect(DATABASE_URL) as c, c.cursor() as cur:
        fid = _firm(cur)
        bad = cur.execute(
            "select outcome, reason from public._checker_place(%s, 'overview', %s::jsonb, %s, 1::smallint, null, null)",
            (fid, '{"label":"Headquarters","value":"NYC"}', ADV),
        ).fetchone()
        assert bad[0] == "blocked" and "fix 7" in bad[1] and "no city" in bad[1]
        assert cur.execute("select count(*) from firm_profile_facts where firm_id = %s", (fid,)).fetchone()[0] == 0
        good = cur.execute(
            "select outcome, reason from public._checker_place(%s, 'overview', %s::jsonb, %s, 1::smallint, null, null)",
            (fid, _item("Menlo Park", "US", "California"), ADV),
        ).fetchone()
        assert good[0] == "blocked" and "routed to firms.hq_city" in good[1]
        assert _row(cur, fid)[:6] == ("Menlo Park", "California", "US", ADV, 1, None)
        src = [{"url": HOUSE, "tier": "T1"}]
        refused = cur.execute(
            "select public._entry_check_reasons(%s::jsonb, 'zz-firm.example')",
            (json.dumps({"records": [{"field_path": "hq", "value": {"city": "London"}, "sources": src}]}),),
        ).fetchone()[0]
        assert any("ISO country" in x for x in refused), refused
        ok = cur.execute(
            "select public._entry_check_reasons(%s::jsonb, 'zz-firm.example')",
            (json.dumps({"records": [{"field_path": "hq", "value": {"city": "London", "region": "England", "country": "GB"}, "sources": src}]}),),
        ).fetchone()[0]
        assert not any("Headquarters" in x or "ISO country" in x for x in ok), ok
        c.rollback()


def test_route_uses_the_conflict_rule():
    with psycopg.connect(DATABASE_URL) as c, c.cursor() as cur:
        fid = _firm(cur, "zz-f7-r")
        reg = "zz-f7-reg"
        cur.execute("update firms set registry_id = %s where id = %s", (reg, fid))
        cur.execute(
            "insert into research_queue (registry_id, name, priority, status) values (%s, 'ZZ F7', 1, 'submitted')",
            (reg,),
        )

        def submit(url, city, country, day, region="California"):
            payload = {"records": [{"record_id": "h1", "field_path": "hq", "as_of": day,
                                    "value": {"city": city, "region": region, "country": country},
                                    "sources": [{"url": url, "retrieved_at": day}]}]}
            cur.execute(
                "insert into bots.research_submissions (registry_id, bot_id, payload, valid) values (%s, 'test-bot', %s, true)",
                (reg, json.dumps(payload)),
            )

        submit("https://zz-firm.example/contact", "Palo Alto", "US", "2025-01-01")
        assert cur.execute("select public._route_hq_record(%s, %s)", (fid, reg)).fetchone()[0] == 1
        assert _row(cur, fid)[:6] == ("Palo Alto", "California", "US", "https://zz-firm.example/contact", 2, "2025-01-01")
        submit(ADV, "Menlo Park", "US", "2021-01-01")
        assert cur.execute("select public._route_hq_record(%s, %s)", (fid, reg)).fetchone()[0] == 1
        assert _row(cur, fid)[:6] == ("Menlo Park", "California", "US", ADV, 1, "2021-01-01")
        submit(HOUSE, "London", "GB", "2026-09-01", "England")
        assert cur.execute("select public._route_hq_record(%s, %s)", (fid, reg)).fetchone()[0] == 0
        assert _row(cur, fid)[0] == "Menlo Park"
        out = cur.execute(
            "select outcome, reason from publish_checks where firm_id = %s and field = 'hq' order by id desc limit 1",
            (fid,),
        ).fetchone()
        assert out[0] == "blocked" and "lower than the stored level 1" in out[1]
        c.rollback()


def test_check8_uses_the_new_country_and_keeps_today_when_empty():
    with psycopg.connect(DATABASE_URL) as c, c.cursor() as cur:
        fid = _firm(cur, "zz-f7-c8")
        cur.execute(
            "insert into firm_check_rows (firm_id, n, title, descr, state) values (%s, 8, 'Registration check', 'd', 'clear')",
            (fid,),
        )
        assert cur.execute("select public._check8_outside_us(%s)", (fid,)).fetchone()[0] is None
        assert cur.execute("select state, why from public._lab_live_pill(%s, 8)", (fid,)).fetchone()[1] == "no IAPD registration row"
        cur.execute("update firms set hq_country = 'US' where id = %s", (fid,))
        assert cur.execute("select public._check8_outside_us(%s)", (fid,)).fetchone()[0] is False
        assert cur.execute("select why from public._lab_live_pill(%s, 8)", (fid,)).fetchone()[0] == "no IAPD registration row"
        cur.execute("update firms set hq_country = 'GB' where id = %s", (fid,))
        state, count, why = cur.execute(
            "select state, count_label, why from public._lab_live_pill(%s, 8)", (fid,)
        ).fetchone()
        assert state == "nc" and "outside the US" in count and why == count
        c.rollback()
