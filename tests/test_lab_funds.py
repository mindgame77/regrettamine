"""Sequoia fund cleanup hides raw notes and does not delete them."""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]


def test_sequoia_fund_cleanup_hides_and_keeps_a_backup():
    sql = (ROOT / "supabase" / "migrations" / "20261028030000_lab_funds_aum.sql").read_text()
    back = (ROOT / "supabase" / "rollbacks" / "20261028030000_lab_funds_aum.sql").read_text()
    assert "slug = 'sequoia'" in sql
    assert "delete from" not in sql.lower()
    assert "hidden = true" in sql
    assert "cleanup_backup" in sql
    assert "$82.2B" in sql
    assert "slug = 'sequoia'" in sql
    assert "delete from" not in back.lower()
