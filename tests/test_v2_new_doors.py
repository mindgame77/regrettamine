"""The door migration names the new shelves and does not put registration on the page."""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIG = ROOT / "supabase/migrations/20261107220000_v2_doors_checker_first.sql"
GUIDE = ROOT / "docs/PAGE_DATA_GUIDE.md"
BRIEF = ROOT / "tools/ingest/external-bot-night-run.md"


def test_migration_opens_doors_and_leaves_the_page_header_alone():
    text = MIG.read_text(encoding="utf-8")
    for table in (
        "v2_investor_principles",
        "v2_firm_stages",
        "v2_firm_industries",
        "v2_firm_types_firms",
        "firm_fund_announcements",
        "v2_firm_check_sizes",
        "v2_firm_former_names",
    ):
        assert table in text
    assert "empty firm field waits for the Checker" in text
    assert "150 characters" in text
    assert "s.is_current and not s.archived" in text
    assert "must not gain registration or street display" in text
    assert "v2_founder_feedback" not in text
    assert "chief executive" not in text


def test_quote_date_may_be_empty_and_is_not_filled():
    text = (ROOT / "supabase/migrations/20261107240000_v2_quote_date_optional.sql").read_text(encoding="utf-8")
    guide = GUIDE.read_text(encoding="utf-8")
    assert "alter column published_at drop not null" in text
    assert "fact := fact - 'published_at'" in text
    assert "current_date" not in text
    assert "Quote date: if the source shows a date use it; if not, leave it empty. Never reject for a missing date. Never use dateModified or archive dates." in guide


def test_docs_have_one_example_per_new_door():
    for path in (GUIDE, BRIEF):
        text = path.read_text(encoding="utf-8")
        for table in (
            "v2_investor_principles",
            "v2_firm_stages",
            "v2_firm_industries",
            "v2_firm_types_firms",
            "firm_fund_announcements",
            "v2_firm_check_sizes",
            "v2_firm_former_names",
        ):
            assert table in text
        assert "150" in text


def test_team_shows_founders_and_current_leader():
    text = (ROOT / "supabase/migrations/20261108000000_v2_team_current_leader.sql").read_text(encoding="utf-8")
    guide = GUIDE.read_text(encoding="utf-8")
    assert "v2_is_leader_title" in text
    assert "and (is_founder or v2_is_leader_title(title))" in text
    assert "source_level = 3 and source_type = 'News' and v2_is_leader_title(title)" in text
    assert "Founders plus whoever runs the firm today, and nobody else" in guide
    assert "reputable dated news source" in guide


def test_fund_announcement_total_keeps_a_tilde_and_skips_without_v2():
    text = (ROOT / "supabase/migrations/20261108020000_v2_fund_announcement_display.sql").read_text(encoding="utf-8")
    assert "to_regclass('public.firm_fund_announcements') is null" in text
    assert "to_regprocedure('public.v2_firm_page(text)') is null" in text
    assert "raise notice 'v2 schema missing, skipped'" in text
    assert "when count(*)=1 then max(a.display)" in text
    assert "bool_or(left(btrim(a.display),1)='~')" in text
    assert "'~'||public._money_display(sum(a.amount_usd),'USD')" in text
    assert "else public._money_display(sum(a.amount_usd),'USD')" in text
    assert "Rows from other dates are not added" in text
    assert "announced_on desc" not in text
    rendered = subprocess.run(
        ["node", "--test", "--test-name-pattern", "keeps the tilde", "tests/funds_line.test.mjs"],
        cwd=ROOT, capture_output=True, text=True,
    )
    assert rendered.returncode == 0, rendered.stdout[-2000:] + rendered.stderr[-2000:]
