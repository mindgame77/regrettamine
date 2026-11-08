"""Average check is one published amount on the stages line."""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIG = ROOT / "supabase/migrations/20261108200000_v2_firm_page_check_size.sql"
GUIDE = ROOT / "docs/PAGE_DATA_GUIDE.md"


def test_page_returns_one_published_amount_text():
    text = MIG.read_text(encoding="utf-8")
    assert "to_regprocedure('public.v2_firm_page(text)') is null" in text
    assert "raise notice 'v2 schema missing, skipped'" in text
    assert "v2_firm_check_sizes is missing" in text
    select = text.split("$new$", 2)[1]
    assert "'check_size'" in select
    assert "nullif(btrim(c.amount_text),'')" in select
    assert "c.is_current and not c.archived" in select
    assert "order by c.read_on desc nulls last, c.id desc limit 1" in select
    assert "source_url" not in select
    assert "min_usd" not in select
    assert "max_usd" not in select
    assert "program_name" not in select
    assert "delete from" not in text.lower()


def test_guide_puts_avg_check_on_the_stages_line():
    guide = GUIDE.read_text(encoding="utf-8")
    assert "B3.10" in guide
    assert "AVG CHECK" in guide
    assert "No current published amount: no label and no divider." in guide
    assert "source URL stay stored and are not drawn" in guide


def test_header_renders_avg_check_only_when_present():
    rendered = subprocess.run(
        ["node", "--test", "tests/firm_header_team.test.mjs"],
        cwd=ROOT, capture_output=True, text=True,
    )
    assert rendered.returncode == 0, rendered.stdout[-2000:] + rendered.stderr[-2000:]
