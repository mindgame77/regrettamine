"""add_firm is one function on the v2 door. It does not replace per-fact submit."""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase/migrations/20261107180000_v2_research_add_firm.sql").read_text()
UNDO = (ROOT / "supabase/rollbacks/20261107180000_v2_research_add_firm.sql").read_text()
FN = (ROOT / "supabase/functions/research-ingest-v2/index.ts").read_text()
GUIDE = (ROOT / "docs/PAGE_DATA_GUIDE.md").read_text()
BRIEF = (ROOT / "tools/ingest/external-bot-night-run.md").read_text()


def test_migration_adds_one_function_and_does_not_touch_submit():
    low = SQL.lower()
    assert "create or replace function public.v2_research_add_firm" in low
    assert "create or replace function public.v2_research_submit" not in low
    assert "v2_checker_action" not in low
    assert "v2_firm_live" not in low
    assert "revoke all on function public.v2_research_add_firm(uuid, jsonb) from public, anon, authenticated" in low
    assert "grant execute on function public.v2_research_add_firm(uuid, jsonb) to service_role" in low
    assert "security definer" in low and "search_path" in low
    assert "to_regclass('public.v2_firms') is null" in low
    assert "drop function if exists public.v2_research_add_firm(uuid, jsonb);" in UNDO.lower()


def test_edge_function_routes_add_firm_without_changing_submit():
    assert 'body.action === "add_firm"' in FN
    assert 'db.rpc("v2_research_add_firm"' in FN
    assert 'db.rpc("v2_research_submit"' in FN
    assert 'db.rpc("v2_checker_action"' in FN
    add = FN.index('body.action === "add_firm"')
    submit = FN.index('db.rpc("v2_research_submit"')
    assert add < submit
    assert "v2_research_submit" not in FN[add:FN.index("list_queue", add)]


def test_researcher_docs_say_v2():
    for text in (GUIDE, BRIEF):
        assert "add_firm" in text
        assert "research-ingest-v2" in text
        assert "source_url" in text and "source_level" in text
        assert "source_date" in text and "source_type" in text
    assert "resend only the corrected" in GUIDE.lower()
    assert "resend only the corrected" in BRIEF.lower()
    assert "dump-1.2" not in BRIEF
    assert "functions/v1/research-ingest\n" not in BRIEF
    assert "visible only to the bot that sent it; never shown to site users" in GUIDE.lower()
    assert "Rejected: link does not open" in GUIDE
