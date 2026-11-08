"""Investment focus is one rule: website labels, else recorded-deal sectors."""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIG = ROOT / "supabase/migrations/20261108070000_investment_focus.sql"
GUIDE = ROOT / "docs/PAGE_DATA_GUIDE.md"
JS = ROOT / "launch/js/company.js"


def test_page_function_returns_the_fallback_without_reusing_the_old_counts():
    text = MIG.read_text(encoding="utf-8")
    assert "to_regprocedure('public.v2_firm_page(text)') is null" in text
    assert "raise notice 'v2 schema missing, skipped'" in text
    assert "'deal_sectors'" in text
    assert "count(distinct d.deal_id)" in text
    assert "checker rejected|superseded" in text
    assert "or d.archived" in text
    assert "nullif(btrim(sc.name),'')" in text
    assert "order by count(distinct d.deal_id) desc, lower(sc.name)" in text
    assert "limit 5" in text
    sql = text.split("$new$", 2)[1]
    assert "sector_12m" not in sql
    assert "_v2_deals" not in sql
    assert "firm_id = 6" in text
    assert "v2_research_submit" in text
    assert "v2_checker_action" in text
    assert "https://lsvp.com/global-presence/lightspeed-united-states/" in text
    assert "2026-11-07" in text
    for label in ("Enterprise", "Consumer", "Health", "Fintech"):
        assert label in text
    assert "delete from" not in text.lower()


def test_guide_states_the_one_rule():
    guide = GUIDE.read_text(encoding="utf-8")
    assert "F.11 Investment focus" in guide
    assert "No per-firm exception" in guide
    assert "under the same Sectors label, with no counts" in guide
    assert "The source stays stored and is not drawn" in guide
    assert "Top sectors from recorded deals" not in guide
    assert "Eligible archived history is included" in guide
    assert "B3.9" in guide
    js = JS.read_text(encoding="utf-8")
    start = js.index("function industryFocus")
    end = js.index("function paintTags")
    body = js[start:end]
    assert "deal_sectors" in body
    assert "htag-src" not in body
    assert "Top sectors from recorded deals" not in body


def test_header_renders_website_focus_and_derived_sectors():
    rendered = subprocess.run(
        ["node", "--test", "tests/investment_focus.test.mjs"],
        cwd=ROOT, capture_output=True, text=True,
    )
    assert rendered.returncode == 0, rendered.stdout[-2000:] + rendered.stderr[-2000:]
