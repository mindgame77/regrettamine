"""Staff and Investment staff leave v2_sec_fact_pills. Private funds stays."""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIG = (ROOT / "supabase/migrations/20261106140000_v2_sec_fact_pills_no_staff.sql").read_text()
UNDO = (ROOT / "supabase/rollbacks/20261106140000_v2_sec_fact_pills_no_staff.sql").read_text()
JS = (ROOT / "launch/js/company.js").read_text()


def test_migration_drops_only_those_two_labels():
    assert "to_regclass('public.v2_sec_fact_pills') is null" in MIG
    assert "delete from public.v2_sec_fact_pills" in MIG
    assert "in ('staff', 'investment staff')" in MIG
    assert "v2_sec_fact_pills_no_staff_labels" in MIG
    assert "fact_label in ('Private funds')" in MIG
    assert "Staff and Investment staff are not accepted" in MIG
    assert "drop table" not in MIG.lower()
    assert "v2_sec_registration" not in MIG
    assert "private funds" not in MIG.split("delete from public.v2_sec_fact_pills", 1)[1].split("if not exists", 1)[0].lower()
    assert "drop constraint if exists v2_sec_fact_pills_no_staff_labels" in UNDO
    assert "Does not put deleted Staff or Investment staff rows back" in UNDO


def test_page_pills_ask_only_for_private_funds():
    start = JS.index("function secPills")
    body = JS[start:JS.index("function secPills") + 900]
    assert "private funds?" in body
    assert "/^staff$/i" not in body
    assert "investment staff/i" not in body
