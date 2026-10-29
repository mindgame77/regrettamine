"""Fix 3: one home per field. AUM and Fund assets live only in firms.aum_amount/aum_currency and
firms.fund_assets_amount/fund_assets_currency. New fact rows that carry them under other labels are not stored."""
import json
import os

import pytest

pytest.importorskip("psycopg")
import psycopg  # noqa: E402

DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")


def _firm(cur, slug="zz-f3"):
    return cur.execute("insert into firms (slug, name, published, data_status) values (%s, 'ZZ F3', true, 'real') returning id",
                       (slug,)).fetchone()[0]


def _one(cur, sql, args=()):
    return cur.execute(sql, args).fetchone()[0]


@pytest.mark.parametrize("label,want", [
    ("AUM", True), ("Regulatory AUM", True), ("RAUM", True), ("Assets under management", True), ("Assets", True),
    ("regulatory_aum", True), ("regulatoryAum", True), ("Fund gross assets", True), ("Gross assets", True),
    ("Fund assets", True), ("Private fund GAV", True), ("Item 5F", True), ("aum_usd", True),
    ("Headquarters", False), ("Asset Fund II", False), ("Funds", False), ("media_x_followers", False), (None, False),
])
def test_label_matcher(label, want):
    with psycopg.connect(DATABASE_URL) as c:
        assert _one(c, "select public._money_home_label(%s)", (label,)) is want


@pytest.mark.parametrize("text,amount,cur", [
    ("RAUM 160,242,886,816 USD (Item 5F)", 160242886816, "USD"), ("$45,502,659,880", 45502659880, "USD"),
    ("EUR 13200000", 13200000, "EUR"), ("$7.8B", None, None), ("160.2 billion", None, None),
    ("$1,500 million", None, None), ("160,242,886,816", None, None),
])
def test_full_number_only(text, amount, cur):
    with psycopg.connect(DATABASE_URL) as c:
        row = c.execute("select amount, currency from public._money_home_full(%s)", (text,)).fetchone()
        assert (row[0], row[1]) == (amount, cur)


def test_blocked_rows_routed_or_logged():
    with psycopg.connect(DATABASE_URL) as c, c.cursor() as cur:
        fid = _firm(cur)
        cur.execute("insert into firm_profile_facts (firm_id, section, label, value) values (%s, 'funds', 'Regulatory AUM', 'RAUM 160,242,886,816 USD')", (fid,))
        cur.execute("insert into firm_profile_facts (firm_id, section, label, hero_label, hero_value, value) values (%s, 'funds', 'Fund gross assets', null, null, 'Fund I · gross assets $7.8B')", (fid,))
        cur.execute("insert into firm_profile_facts (firm_id, section, label, value) values (%s, 'overview', 'Headquarters', 'NYC')", (fid,))
        cur.execute("insert into vc_source_facts (firm_id, fact_type, section, value, data_status) values (%s, 'fund_fact', 'checks', %s, 'real')",
                    (fid, json.dumps({"field": "regulatory_aum", "value": "RAUM 1,000,000,000 USD"})))
        cur.execute("insert into list_items (firm_id, group_key, name, value, note) values (%s, 'facts', 'Regulatory AUM', '$45.50B', 'short form')", (fid,))
        cur.execute("insert into timeline_events (firm_id, date_label, kind, body) values (%s, '2026', 'aum', 'AUM: $5B')", (fid,))
        # Only the HQ card is stored.
        assert _one(cur, "select count(*) from firm_profile_facts where firm_id = %s", (fid,)) == 1
        for t in ("vc_source_facts", "list_items", "timeline_events"):
            assert _one(cur, f"select count(*) from {t} where firm_id = %s", (fid,)) == 0, t
        # Fix 4b: these rows have no source link, so the number is not copied. The rows are still not stored.
        assert cur.execute("select aum_amount, aum_currency from firms where id = %s", (fid,)).fetchone() == (None, None)
        assert _one(cur, "select fund_assets_amount from firms where id = %s", (fid,)) is None  # per-fund gross assets never routed
        log = cur.execute("select table_name, routed_to, reason from money_home_blocked where firm_id = %s order by id", (fid,)).fetchall()
        assert [x[0] for x in log] == ["firm_profile_facts", "firm_profile_facts", "vc_source_facts", "list_items", "timeline_events"]
        assert log[0][1] is None and all("One home per field (fix 3)" in x[2] for x in log)
        assert "no acceptable source" in log[0][2] and "no full number" in log[3][2]
        c.rollback()


def test_existing_rows_kept_and_editable():
    with psycopg.connect(DATABASE_URL) as c, c.cursor() as cur:
        fid = _firm(cur)
        cur.execute("set local session_replication_role = replica")  # a row from before fix 3
        rid = _one(cur, "insert into firm_profile_facts (firm_id, section, label, value) values (%s, 'funds', 'Regulatory AUM', 'old') returning id", (fid,))
        cur.execute("set local session_replication_role = origin")
        cur.execute("update firm_profile_facts set value = 'edited', hero_label = 'Regulatory AUM' where id = %s", (rid,))
        assert _one(cur, "select value from firm_profile_facts where id = %s", (rid,)) == "edited"
        # Relabelling a normal row into AUM is blocked.
        hq = _one(cur, "insert into firm_profile_facts (firm_id, section, label, value) values (%s, 'overview', 'Headquarters', 'NYC') returning id", (fid,))
        cur.execute("update firm_profile_facts set label = 'AUM' where id = %s", (hq,))
        assert _one(cur, "select label from firm_profile_facts where id = %s", (hq,)) == "Headquarters"
        c.rollback()


def test_entry_check_rejects_other_labels():
    src = [{"url": "https://www.sec.gov/x", "tier": "T1"}]
    bad = [{"field_path": "funds", "value": {"name": "F", "aum_usd": 5000000000}, "sources": src},
           {"field_path": "latestRaise", "value": {"amount_usd": 5000000000, "label": "Regulatory AUM"}, "sources": src}]
    ok = [{"field_path": "aum", "value": {"amount_usd": 5000000000, "basis": "form_adv_raum"}, "sources": src},
          {"field_path": "funds", "value": {"name": "Asset Fund II", "size_usd": 100000000}, "sources": src}]
    with psycopg.connect(DATABASE_URL) as c:
        for r in bad:
            reasons = _one(c, "select public._entry_check_reasons(%s::jsonb, null)", (json.dumps({"records": [r]}),))
            assert any("one home" in x for x in reasons), reasons
        reasons = _one(c, "select public._entry_check_reasons(%s::jsonb, null)", (json.dumps({"records": ok}),))
        assert not any("one home" in x for x in reasons), reasons
        sec = {"sections": {"Overview": [{"label": "Regulatory AUM", "value": "$5B", "source": "https://www.sec.gov/x"}]}}
        assert _one(c, "select public._money_home_item(null, %s::jsonb)", (json.dumps(sec["sections"]["Overview"][0]),)) == "Regulatory AUM"


def test_route_aum_record_fills_empty_home_only():
    with psycopg.connect(DATABASE_URL) as c, c.cursor() as cur:
        fid = _firm(cur)
        assert _one(cur, "select public._route_aum_record(%s, null)", (fid,)) == 0
        src = (__import__("pathlib").Path(__file__).resolve().parents[1] / "supabase" / "migrations" / "20261029280000_fix3_one_home_aum.sql").read_text()
        body = src.split("FUNCTION public.promote_bot_facts", 1)[1]
        assert "('aum', 'funds', 'Assets under management'" not in body and "_route_aum_record(p_firm, qid)" in body
        c.rollback()
