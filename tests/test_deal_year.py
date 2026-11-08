"""A bare year is accepted by the deal door and shown as the year."""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIG = ROOT / "supabase/migrations/20261108080000_v2_deal_year_only.sql"
GUIDE = ROOT / "docs/PAGE_DATA_GUIDE.md"


def test_door_accepts_a_bare_year_without_touching_the_page_function():
    text = MIG.read_text(encoding="utf-8")
    assert "to_regprocedure('public.v2_research_submit(uuid,jsonb,boolean)') is null" in text
    assert "raise notice 'v2 schema missing, skipped'" in text
    assert "tbl = 'v2_deals'" in text
    assert "~ '^\\d{4}$'" in text
    assert "'-01-01'" in text
    assert "'deal_date_precision', 'year'" in text
    assert "v2_firm_page is not changed" in text
    assert "CREATE OR REPLACE FUNCTION public.v2_firm_page" not in text
    assert "create table" not in text.lower()
    assert "add column" not in text.lower()


def test_rulebook_matches_this_year_and_the_year_bar():
    guide = GUIDE.read_text(encoding="utf-8")
    assert "Deals, this year" in guide
    assert "This year / All time" in guide
    assert "one bar per calendar year" in guide
    assert "A date may be a bare year" in guide
    assert "v2_firm_page` itself is not changed" in guide


def test_page_renders_this_year_and_the_year_bar():
    rendered = subprocess.run(
        ["node", "--test", "tests/deal_year.test.mjs"],
        cwd=ROOT, capture_output=True, text=True,
    )
    assert rendered.returncode == 0, rendered.stdout[-2000:] + rendered.stderr[-2000:]
