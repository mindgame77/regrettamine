"""Fix 4b: source level and source date for AUM and Fund assets.

Level 1 is a SEC Form ADV link. Level 2 is the firm's own website. Level 3 is a DEF 14A, a press
release or news on another site, or another trusted page. AUM takes level 1, else level 2, else level 3
only when no level 1 or 2 is stored. Level 1 or 2 always replaces a level 3 AUM. Fund assets take level 1
only. A higher level replaces the stored amount and link. A lower level is blocked. The same level
replaces only when its source date is newer. Every case below runs in a transaction that rolls back.
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
DEF = "https://www.sec.gov/Archives/edgar/data/1/0001/def14a.htm"
ROOT = Path(__file__).resolve().parents[1]
MIGRATION = (ROOT / "supabase/migrations/20261029310000_fix4b_source_levels.sql").read_text()


def _firm(cur, slug="zz-f4b"):
    return cur.execute(
        "insert into firms (slug, name, published, data_status, primary_domain) "
        "values (%s, 'ZZ F4b', true, 'real', 'zz-firm.example') returning id",
        (slug,),
    ).fetchone()[0]


def _place(cur, fid, kind, amount, currency, url, day):
    return cur.execute(
        "select public._place_money_source(%s, %s, %s, %s, %s, %s)",
        (fid, kind, amount, currency, url, day),
    ).fetchone()[0]


def _row(cur, fid):
    return cur.execute(
        "select aum_amount, aum_source_url, aum_source_level, aum_source_date::text, "
        "fund_assets_amount, fund_assets_source_url, fund_assets_source_level, fund_assets_source_date::text, aum_billions "
        "from firms where id = %s",
        (fid,),
    ).fetchone()


def test_migration_does_no_data_work_and_leaves_other_writers_alone():
    assert "sec_crd" not in MIGRATION
    for name in (
        "firm_page", "firm_list_row", "landing_funds", "promote_bot_facts",
        "_checker_write", "checker_publish_submission", "checker_publish_firm",
    ):
        assert f"function public.{name}" not in MIGRATION
    assert "insert into public.firms" not in MIGRATION.lower()
    assert "insert into firms" not in MIGRATION.lower()


@pytest.mark.parametrize("url,level", [
    (ADV, 1),
    ("https://adviserinfo.sec.gov/firm/summary/157373", 1),
    ("https://www.sec.gov/about/forms/formadv.pdf", 1),
    ("https://zz-firm.example/aum", 2),
    ("https://www.zz-firm.example/aum", 2),
    ("https://blog.zz-firm.example/aum", 2),
    ("https://zz-firm.example/press-release/aum", 2),
    (DEF, 3),
    ("https://example.com/press-release/fund", 3),
    ("https://www.sec.gov/news/press-release/2026-1", 3),
    ("https://techcrunch.com/2026/01/01/raises", 3),
    ("https://www.reuters.com/markets/fund", 3),
    ("https://example.com/aum", None),
    ("https://zz-firm.example.evil.com/aum", None),
    ("http://adviserinfo.sec.gov/firm/summary/1", None),
    (None, None),
])
def test_source_level(url, level):
    with psycopg.connect(DATABASE_URL) as c, c.cursor() as cur:
        fid = _firm(cur)
        got = cur.execute("select public._money_source_level(%s, %s)", (fid, url)).fetchone()[0]
        assert got == level
        c.rollback()


def test_trusted_page_is_level_3_for_fund_amounts_only():
    with psycopg.connect(DATABASE_URL) as c, c.cursor() as cur:
        fid = _firm(cur)
        cur.execute("insert into trusted_source_domains (domain, label, kind) values ('zztrusted.example', 'ZZ', 'regulator')")
        assert cur.execute("select public._money_source_level(%s, %s)", (fid, "https://zztrusted.example/page")).fetchone()[0] == 3
        assert _place(cur, fid, "aum", 5000000000, "USD", "https://zztrusted.example/page", "2026-01-01") is None
        assert _row(cur, fid)[:4] == (5000000000, "https://zztrusted.example/page", 3, "2026-01-01")
        assert "no level 1 or 2" in _place(cur, fid, "fund_assets", 5000000000, "USD", "https://techcrunch.com/2026/02/02/x", "2026-02-02")
        assert _row(cur, fid)[4] is None
        c.rollback()


def test_constraint_allows_def14a_for_aum_and_refuses_it_for_fund_assets():
    with psycopg.connect(DATABASE_URL) as c, c.cursor() as cur:
        fid = _firm(cur)
        cur.execute("update firms set aum_source_url = %s where id = %s", (DEF, fid))
        cur.execute("update firms set aum_source_url = 'https://zz-firm.example/aum' where id = %s", (fid,))
        with pytest.raises(psycopg.errors.CheckViolation):
            cur.execute("update firms set fund_assets_source_url = %s where id = %s", (DEF, fid))
        c.rollback()


def test_each_conflict_case_rolls_back():
    """One transaction. Higher replaces. Lower is blocked. Same level needs a newer date. Then the transaction rolls back."""
    with psycopg.connect(DATABASE_URL) as c, c.cursor() as cur:
        fid = _firm(cur)
        cur.execute("update firms set aum_billions = 1.5 where id = %s", (fid,))
        # Empty field: level 2 is stored.
        assert _place(cur, fid, "aum", 3000000000, "USD", "https://zz-firm.example/aum", "2025-06-01") is None
        assert _row(cur, fid)[:4] == (3000000000, "https://zz-firm.example/aum", 2, "2025-06-01")
        # Higher level replaces the amount and the link even when its date is older.
        assert _place(cur, fid, "aum", 9000000000, "USD", ADV, "2020-01-01") is None
        assert _row(cur, fid)[:4] == (9000000000, ADV, 1, "2020-01-01")
        # Lower level is refused. The stored value and link stay.
        why = _place(cur, fid, "aum", 1000000000, "USD", "https://zz-firm.example/other", "2026-01-01")
        assert why and "lower than the stored level 1" in why
        assert _row(cur, fid)[:4] == (9000000000, ADV, 1, "2020-01-01")
        # Same level, newer date, replaces.
        assert _place(cur, fid, "aum", 9100000000, "USD", ADV, "2026-03-01") is None
        assert _row(cur, fid)[:4] == (9100000000, ADV, 1, "2026-03-01")
        # Same level, older date, blocked.
        why = _place(cur, fid, "aum", 1000000000, "USD", ADV, "2024-01-01")
        assert why and "not newer" in why
        # Same level, same date, blocked.
        why = _place(cur, fid, "aum", 1000000000, "USD", ADV, "2026-03-01")
        assert why and "not newer" in why
        # Same level, no date, blocked.
        why = _place(cur, fid, "aum", 1000000000, "USD", ADV, None)
        assert why and "not newer" in why
        assert _row(cur, fid)[:4] == (9100000000, ADV, 1, "2026-03-01")
        # A stored level 1 blocks level 3 (news, DEF 14A, and a non-firm press release).
        for url in ("https://www.bloomberg.com/news/x", DEF, "https://example.com/press-release/fund"):
            why = _place(cur, fid, "aum", 1000000000, "USD", url, "2026-04-01")
            assert why and "lower than the stored level 1" in why
        assert _row(cur, fid)[:4] == (9100000000, ADV, 1, "2026-03-01")
        # Fund assets: level 1 only. Level 2 and level 3 are blocked. Level 1 is stored, then an older one is blocked.
        assert "source level 1 only" in _place(cur, fid, "fund_assets", 2000000000, "USD", "https://zz-firm.example/gav", "2026-01-01")
        assert _row(cur, fid)[4] is None
        assert _place(cur, fid, "fund_assets", 2000000000, "USD", ADV, "2024-01-01") is None
        assert _row(cur, fid)[4:8] == (2000000000, ADV, 1, "2024-01-01")
        why = _place(cur, fid, "fund_assets", 3000000000, "USD", ADV, "2023-01-01")
        assert why and "not newer" in why
        assert _place(cur, fid, "fund_assets", 4000000000, "USD", ADV, "2026-08-01") is None
        assert _row(cur, fid)[4:8] == (4000000000, ADV, 1, "2026-08-01")
        # The legacy short-form column is not touched.
        assert _row(cur, fid)[8] == 1.5
        c.rollback()
        assert c.execute("select id from firms where slug = 'zz-f4b'").fetchone() is None


def test_aum_level_3_only_when_no_level_1_or_2():
    """Level 3 fills an empty AUM. Level 1 or 2 replaces it even when the level 3 date is newer."""
    with psycopg.connect(DATABASE_URL) as c, c.cursor() as cur:
        fid = _firm(cur, "zz-f4b-l3")
        assert _place(cur, fid, "aum", 2000000000, "USD", DEF, "2024-01-01") is None
        assert _row(cur, fid)[:4] == (2000000000, DEF, 3, "2024-01-01")
        # Same level: a newer news page replaces the DEF 14A. An older press release does not.
        assert _place(cur, fid, "aum", 2100000000, "USD", "https://techcrunch.com/2026/01/01/raises", "2026-01-01") is None
        assert _row(cur, fid)[:4] == (2100000000, "https://techcrunch.com/2026/01/01/raises", 3, "2026-01-01")
        why = _place(cur, fid, "aum", 1000000000, "USD", "https://example.com/press-release/old", "2020-01-01")
        assert why and "not newer" in why
        assert _row(cur, fid)[2] == 3
        # Level 2 replaces level 3 even though its date is older.
        assert _place(cur, fid, "aum", 4000000000, "USD", "https://zz-firm.example/aum", "2019-01-01") is None
        assert _row(cur, fid)[:4] == (4000000000, "https://zz-firm.example/aum", 2, "2019-01-01")
        why = _place(cur, fid, "aum", 5000000000, "USD", DEF, "2026-06-01")
        assert why and "lower than the stored level 2" in why
        assert _row(cur, fid)[:4] == (4000000000, "https://zz-firm.example/aum", 2, "2019-01-01")
        # Level 1 replaces level 3 the same way, and a later level 3 stays blocked.
        cur.execute(
            "update firms set aum_amount = null, aum_currency = null, aum_source_url = null, "
            "aum_source_level = null, aum_source_date = null where id = %s",
            (fid,),
        )
        assert _place(cur, fid, "aum", 2000000000, "USD", "https://www.reuters.com/markets/fund", "2025-05-01") is None
        assert _place(cur, fid, "aum", 9000000000, "USD", ADV, "2020-01-01") is None
        assert _row(cur, fid)[:4] == (9000000000, ADV, 1, "2020-01-01")
        why = _place(cur, fid, "aum", 1000000000, "USD", "https://www.sec.gov/news/press-release/2026-1", "2026-08-01")
        assert why and "lower than the stored level 1" in why
        assert _row(cur, fid)[:4] == (9000000000, ADV, 1, "2020-01-01")
        # On one record, a Form ADV link wins over a newer DEF 14A.
        picked = cur.execute(
            "select url, source_level from public._money_pick_source(%s, 'aum', %s::jsonb, null)",
            (fid, json.dumps([
                {"url": DEF, "retrieved_at": "2026-01-01"},
                {"url": ADV, "retrieved_at": "2020-01-01"},
            ])),
        ).fetchone()
        assert picked[0] == ADV and picked[1] == 1
        # Fund assets still refuse a DEF 14A and a news page.
        assert "no level 1 or 2" in _place(cur, fid, "fund_assets", 2000000000, "USD", DEF, "2026-01-01")
        assert _row(cur, fid)[4] is None
        c.rollback()


def test_guard_routes_only_an_accepted_source():
    with psycopg.connect(DATABASE_URL) as c, c.cursor() as cur:
        fid = _firm(cur, "zz-f4b-g")
        cur.execute(
            "insert into vc_source_facts (firm_id, fact_type, section, value, source_url, retrieved_at, data_status) "
            "values (%s, 'fund_fact', 'funds', %s, %s, '2024-05-01', 'real')",
            (fid, json.dumps({"field": "regulatory_aum", "value": "RAUM 5,000,000,000 USD"}), ADV),
        )
        assert _row(cur, fid)[:4] == (5000000000, ADV, 1, "2024-05-01")
        assert cur.execute("select count(*) from vc_source_facts where firm_id = %s", (fid,)).fetchone()[0] == 0
        cur.execute(
            "insert into vc_source_facts (firm_id, fact_type, section, value, source_url, retrieved_at, data_status) "
            "values (%s, 'fund_fact', 'funds', %s, %s, '2026-01-01', 'real')",
            (fid, json.dumps({"label": "Fund assets", "value": "Fund assets 7,000,000,000 USD"}), "https://zz-firm.example/gav"),
        )
        assert _row(cur, fid)[4] is None
        reason = cur.execute(
            "select reason from money_home_blocked where firm_id = %s order by id desc limit 1", (fid,)
        ).fetchone()[0]
        assert "source level 1 only" in reason and "One home per field (fix 3)" in reason
        c.rollback()


def test_route_uses_the_conflict_rule():
    with psycopg.connect(DATABASE_URL) as c, c.cursor() as cur:
        fid = _firm(cur, "zz-f4b-r")
        reg = "zz-f4b-reg"
        cur.execute(
            "insert into research_queue (registry_id, name, priority, status) values (%s, 'ZZ F4b', 1, 'submitted')",
            (reg,),
        )

        def submit(url, amount, day, gav=None):
            value = {"amount_usd": amount, "basis": "self_reported" if "example" in url else "form_adv_raum"}
            if gav:
                value["private_fund_gav_usd"] = gav
            payload = {"records": [{"record_id": "a1", "field_path": "aum", "as_of": day, "value": value,
                                    "sources": [{"url": url, "retrieved_at": day}]}]}
            cur.execute(
                "insert into bots.research_submissions (registry_id, bot_id, payload, valid) values (%s, 'test-bot', %s, true)",
                (reg, json.dumps(payload)),
            )

        submit("https://zz-firm.example/aum", 3000000000, "2025-01-01")
        assert cur.execute("select public._route_aum_record(%s, %s)", (fid, reg)).fetchone()[0] == 1
        assert _row(cur, fid)[:4] == (3000000000, "https://zz-firm.example/aum", 2, "2025-01-01")
        submit(ADV, 8000000000, "2021-01-01", gav=6000000000)
        assert cur.execute("select public._route_aum_record(%s, %s)", (fid, reg)).fetchone()[0] == 2
        assert _row(cur, fid)[:8] == (8000000000, ADV, 1, "2021-01-01", 6000000000, ADV, 1, "2021-01-01")
        submit("https://zz-firm.example/later", 1000000000, "2026-09-01")
        assert cur.execute("select public._route_aum_record(%s, %s)", (fid, reg)).fetchone()[0] == 0
        assert _row(cur, fid)[:4] == (8000000000, ADV, 1, "2021-01-01")
        out = cur.execute(
            "select outcome, reason from publish_checks where firm_id = %s and field = 'aum' order by id desc limit 1",
            (fid,),
        ).fetchone()
        assert out[0] == "blocked" and "lower than the stored level 1" in out[1]
        blocked = cur.execute(
            "select reason from money_home_blocked where firm_id = %s and op = 'route' order by id desc limit 1",
            (fid,),
        ).fetchone()[0]
        assert "lower than the stored level 1" in blocked
        c.rollback()


def test_readers_are_unchanged():
    with psycopg.connect(DATABASE_URL) as c, c.cursor() as cur:
        def src(name):
            row = cur.execute("select prosrc from pg_proc where proname = %s", (name,)).fetchone()
            return row[0] if row else ""
        assert "aum_source_level" not in src("firm_page")
        assert "aum_source_level" not in src("_checker_write")
        assert "aum_source_level" not in src("promote_bot_facts")
        assert "aum_billions" in src("firm_list_row")
        assert "aum_amount" not in src("firm_list_row")
        assert "aum_source_level" not in src("firm_list_row")
