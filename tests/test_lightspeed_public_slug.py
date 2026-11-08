"""Lightspeed's live slug is the short public path, and only that firm's slug columns change."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase/migrations/20261108040000_lightspeed_public_slug.sql").read_text()
UNDO = (ROOT / "supabase/rollbacks/20261108040000_lightspeed_public_slug.sql").read_text()


def _body(text):
    lines = [line for line in text.splitlines() if not line.strip().startswith("--")]
    return "\n".join(lines).lower()


def test_lightspeed_slug_update_is_firm_6_only_and_keeps_rows():
    low = _body(SQL)
    assert "update public.v2_firms" in low
    assert "update public.v2_firm_live" in low
    assert "slug = 'lightspeed'" in low
    assert "slug = 'lightspeed-venture-partners'" in low
    assert "firm_id = 6" in low
    assert "display_name = 'lightspeed venture partners'" in low
    assert "delete " not in low
    assert "drop " not in low
    assert "to_regclass('public.v2_firms') is null" in low
    assert "firm_id <> 6" in low
    for other in ("a16z", "sequoia", "y-combinator", "accel", "generalcatalyst"):
        assert other not in low
    assert "update public.firms" not in low
    assert "launch_page" not in low


def test_rollback_restores_the_long_slug_without_deleting():
    low = _body(UNDO)
    assert "slug = 'lightspeed-venture-partners'" in low
    assert "firm_id = 6" in low
    assert "delete " not in low
    assert "drop " not in low
