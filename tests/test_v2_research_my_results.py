"""v2 door action results: a research bot reads its own checker outcomes and empty boxes."""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase/migrations/20261110060000_v2_research_my_results.sql").read_text()
UNDO = (ROOT / "supabase/rollbacks/20261110060000_v2_research_my_results.sql").read_text()
FN = (ROOT / "supabase/functions/research-ingest-v2/index.ts").read_text()
OLD_DOOR = (ROOT / "supabase/functions/research-ingest/index.ts").read_text()


def test_migration_is_read_only_v2_and_server_only():
    low = SQL.lower()
    for bad in ("alter table", "drop table", "insert into", "update ", "delete from", "create policy", "create trigger"):
        assert bad not in low, bad
    assert "bots.research_submissions" not in low
    assert "v2_research_submissions" in SQL
    assert "v2_checker_verdicts.reason" in SQL or "v.reason" in SQL
    assert "v2_research_submissions.bot_key_id" in SQL or "s.bot_key_id" in SQL
    assert "k.active" in SQL and "k.bot_id" in SQL
    assert "create or replace function public.v2_research_my_results(" in low and "p_key uuid" in low
    assert "to_regclass('public.v2_firms') is null" in low
    assert "revoke all on function public.v2_research_my_results(uuid, int, int, bigint) from public, anon, authenticated" in low
    assert "grant execute on function public.v2_research_my_results(uuid, int, int, bigint) to service_role" in low
    assert "grant execute on function public._v2_research_not_sent" not in low
    assert "security definer" in low
    assert "look for it." in SQL
    assert "drop function if exists public.v2_research_my_results(uuid, int, int, bigint);" in UNDO
    assert "drop function if exists public._v2_research_my_result_items(bigint, int, bigint);" in UNDO
    assert "drop function if exists public._v2_research_not_sent(bigint);" in UNDO


def test_edge_routes_results_from_the_key_without_changing_other_actions():
    assert 'body.action === "results"' in FN
    assert 'db.rpc("v2_research_my_results"' in FN
    assert 'p_key: auth.key_id' in FN
    block_start = FN.index('body.action === "results"')
    block = FN[block_start:FN.index('body.action !== "submit"', block_start)]
    assert "body.bot_id" not in block
    assert 'db.rpc("v2_research_claim"' in FN
    assert 'db.rpc("v2_research_done"' in FN
    assert 'db.rpc("v2_research_submit"' in FN
    assert 'db.rpc("v2_research_add_firm"' in FN
    assert 'db.rpc("v2_checker_action"' in FN
    assert "action must be submit, add_firm, claim, done, results, list_queue or verdict" in FN
    assert "action" in FN and 'results' in FN[FN.index("const HINT"):FN.index(";", FN.index("const HINT"))]
    assert "v2_research_my_results" not in OLD_DOOR
