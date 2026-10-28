"""Checks are off (Alex 2026-10-28): nothing refills firm_check_rows; pages get a static list of 10 'not checked' rows."""
import pathlib, re

MIG = pathlib.Path(__file__).resolve().parents[1] / "supabase" / "migrations" / "20261029031000_checks_off.sql"


def test_checks_off_migration():
    s = MIG.read_text()
    for t in ("checks_from_upload", "zz_check_request_done"):
        assert f"drop trigger if exists {t} on bots.research_submissions" in s
    assert "'zz_pills_mark', 'zz_pills_flush'" in s
    assert "checker_on_submission" not in re.sub(r"--.*", "", s)  # publish pipeline stays
    assert "truncate public.firm_check_pills_dirty, public.firm_check_pills, public.firm_check_rows" in s
    assert "insert into firm_check_rows" not in s


def test_placeholder_list_has_ten_checks():
    s = MIG.read_text()
    block = s[s.index("function public._check_placeholders()"):s.index("create or replace function public._firm_checks(")]
    assert len(re.findall(r"\((\d+), '", block)) == 10
    assert "'state', 'nc'" in block
