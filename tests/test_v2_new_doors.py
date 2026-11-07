"""The door migration names the new shelves and does not put registration on the page."""
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
