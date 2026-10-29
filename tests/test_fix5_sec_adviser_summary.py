"""Fix 5: a new SEC adviser summary is not stored.
A real regulator action, the Form ADV link, and the check 8 registration line still go in.
The five rows that were already stored were deleted after Alex said yes (t2894u). The export keeps the copy."""
import json
import os
from pathlib import Path

import pytest

pytest.importorskip("psycopg")
import psycopg  # noqa: E402

DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
ROOT = Path(__file__).resolve().parents[1]
SUMMARY = (
    "IAPD/FINRA firm IA disclosure flag = N. Registered investment adviser EXAMPLE, "
    "SEC 801-1, which counts as Clear. Item 5F regulatory AUM $1. Schedule A: Someone."
)
KEEP = (
    "5472859e-1488-a40e-c4cb-f98a46a6b3af",
    "41a8d87f-c6d6-8a47-0dc3-c0e4fbdb73c0",
    "95b4a2d3-0734-c461-45a3-6faf1d2acf46",
    "b234b35f-5e9d-52e4-7bb8-839bdcc21966",
    "42ed7a0e-7ffc-0f46-e31d-be903d1dd585",
)


def _firm(cur, slug="zz-f5"):
    return cur.execute(
        "insert into firms (slug, name, published, data_status) values (%s, 'ZZ F5', true, 'real') returning id",
        (slug,),
    ).fetchone()[0]


def test_summary_predicate():
    sql = "select public._sec_adviser_summary(%s, %s)"
    with psycopg.connect(DATABASE_URL) as c:
        assert c.execute(sql, ("regulator", SUMMARY)).fetchone()[0] is True
        assert c.execute(sql, ("regulator", "SEC adviser summary for Example")).fetchone()[0] is True
        assert c.execute(sql, ("regulator", "SEC order IA-5079 (Dyal Funds expense allocation)")).fetchone()[0] is False
        assert c.execute(sql, ("regulator", "SEC")).fetchone()[0] is False
        assert c.execute(sql, ("case", SUMMARY)).fetchone()[0] is False
        assert c.execute(sql, ("context", SUMMARY)).fetchone()[0] is False


def test_new_summary_is_blocked_and_a_real_action_is_kept():
    with psycopg.connect(DATABASE_URL) as c, c.cursor() as cur:
        fid = _firm(cur)
        cur.execute(
            "insert into firm_legal_items (firm_id, grp, title) values (%s, 'regulator', %s)",
            (fid, SUMMARY),
        )
        assert cur.execute("select count(*) from firm_legal_items where firm_id = %s", (fid,)).fetchone()[0] == 0
        row = cur.execute(
            "select outcome, reason from publish_checks where firm_id = %s and field = 'sec_adviser_summary'",
            (fid,),
        ).fetchone()
        assert row[0] == "blocked" and "fix 5" in row[1] and "Form ADV" in row[1] and "check 8" in row[1]
        assert cur.execute(
            "select count(*) from money_home_blocked where firm_id = %s and label = 'SEC adviser summary'",
            (fid,),
        ).fetchone()[0] == 1
        kept = cur.execute(
            "insert into firm_legal_items (firm_id, grp, title, status_label) "
            "values (%s, 'regulator', 'SEC order IA-5079', 'Settled') returning id",
            (fid,),
        ).fetchone()[0]
        assert kept is not None
        # Renaming a real action into the summary is refused; the action stays.
        cur.execute("update firm_legal_items set title = %s where id = %s", (SUMMARY, kept))
        assert cur.execute("select title from firm_legal_items where id = %s", (kept,)).fetchone()[0] == "SEC order IA-5079"
        # Check 8 registration line and a Form ADV profile fact are not this row.
        cur.execute(
            "insert into vc_source_facts (firm_id, fact_type, section, value, source_url, retrieved_at, data_status) "
            "values (%s, 'fund_fact', 'checks', %s, 'https://adviserinfo.sec.gov/firm/summary/1', now(), 'real')",
            (fid, json.dumps({"field": "registration_status", "value": "Registered"})),
        )
        cur.execute(
            "insert into firm_profile_facts (firm_id, section, label, value) "
            "values (%s, 'overview', 'Form ADV', 'Form ADV filed')",
            (fid,),
        )
        assert cur.execute(
            "select count(*) from vc_source_facts where firm_id = %s and value->>'field' = 'registration_status'",
            (fid,),
        ).fetchone()[0] == 1
        assert cur.execute(
            "select count(*) from firm_profile_facts where firm_id = %s and label = 'Form ADV'",
            (fid,),
        ).fetchone()[0] == 1
        c.rollback()


def test_existing_summary_stays_editable():
    with psycopg.connect(DATABASE_URL) as c, c.cursor() as cur:
        fid = _firm(cur, "zz-f5b")
        cur.execute("set local session_replication_role = replica")
        rid = cur.execute(
            "insert into firm_legal_items (firm_id, grp, title) values (%s, 'regulator', %s) returning id",
            (fid, SUMMARY),
        ).fetchone()[0]
        cur.execute("set local session_replication_role = origin")
        cur.execute("update firm_legal_items set note = 'kept' where id = %s", (rid,))
        assert cur.execute("select note, title from firm_legal_items where id = %s", (rid,)).fetchone()[0] == "kept"
        c.rollback()


def test_checker_does_not_write_a_summary():
    with psycopg.connect(DATABASE_URL) as c, c.cursor() as cur:
        fid = _firm(cur, "zz-f5c")
        assert cur.execute(
            "select public._checker_write(%s, 'legal', %s::jsonb, 'https://adviserinfo.sec.gov/firm/summary/1', 1::smallint, null)",
            (fid, json.dumps({"title": SUMMARY})),
        ).fetchone()[0] is None
        assert cur.execute("select count(*) from firm_legal_items where firm_id = %s", (fid,)).fetchone()[0] == 0
        out = cur.execute(
            "select outcome, reason from public._checker_place(%s, 'legal', %s::jsonb, 'https://adviserinfo.sec.gov/firm/summary/1', 1::smallint, null, null)",
            (fid, json.dumps({"title": SUMMARY})),
        ).fetchone()
        assert out[0] == "blocked" and "fix 5" in out[1]
        # A normal legal title is still written.
        rid = cur.execute(
            "select public._checker_write(%s, 'legal', %s::jsonb, 'https://www.courtlistener.com/docket/1/', 1::smallint, null)",
            (fid, json.dumps({"title": "Doe v. Example", "status": "Active", "date": "2024-01-01"})),
        ).fetchone()[0]
        assert rid is not None
        assert cur.execute("select grp, title from firm_legal_items where id = %s", (rid,)).fetchone() == ("context", "Doe v. Example")
        c.rollback()


def test_entry_check_refuses_the_summary_and_keeps_a_real_action():
    summary = {"records": [{"field_path": "regulatoryActions", "value": {"title": SUMMARY}, "sources": [{"url": "https://adviserinfo.sec.gov/firm/summary/1", "tier": "T1"}]}]}
    action = {"records": [{"field_path": "regulatoryActions", "value": {"title": "SEC order IA-5079", "status": "Settled"}, "sources": [{"url": "https://www.sec.gov/enforcement/ia-5079", "tier": "T1"}]}]}
    with psycopg.connect(DATABASE_URL) as c:
        bad = c.execute("select public._entry_check_reasons(%s::jsonb, null)", (json.dumps(summary),)).fetchone()[0]
        assert any("fix 5" in x for x in bad), bad
        good = c.execute("select public._entry_check_reasons(%s::jsonb, null)", (json.dumps(action),)).fetchone()[0]
        assert not any("fix 5" in x for x in good), good


def test_scripts_name_the_five_rows_and_the_migration_does_not_delete_them():
    mig = (ROOT / "supabase/migrations/20261029320000_fix5_sec_adviser_summary.sql").read_text().lower()
    assert "delete from firm_legal_items" not in mig
    assert "delete from public.firm_legal_items" not in mig
    backup = (ROOT / "supabase/rollbacks/20261029320000_fix5_sec_summary_backup.sql").read_text()
    delete = (ROOT / "supabase/rollbacks/20261029320000_fix5_sec_summary_delete_restore.sql").read_text()
    export = (ROOT / "supabase/rollbacks/20261029320000_fix5_sec_summary_export.json").read_text()
    for i in KEEP:
        assert i in backup and i in delete and i in export
    assert "create schema" not in backup.lower()
    assert "t2894u" in delete.lower()
    assert "raise exception" not in delete.lower()
    assert "0423628e-8b51-5095-a1a0-86409ff438ee" in delete
    assert "disable trigger sec_summary_guard" in delete.lower()
    assert delete.strip().endswith("rollback;")
