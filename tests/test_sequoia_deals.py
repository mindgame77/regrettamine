"""The Sequoia deal mover only reads Sequoia and does not delete timeline rows."""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]


def test_sequoia_deal_mover_is_scoped_and_keeps_rows():
    sql = (ROOT / "supabase" / "migrations" / "20261028050000_sequoia_timeline_deals.sql").read_text()
    assert "slug = 'sequoia'" in sql
    assert "p_apply" in sql
    assert "delete from" not in sql.lower()
    assert "timeline_events" in sql
