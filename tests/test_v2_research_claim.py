"""Claim and done sit on the v2 door. They do not replace submit or read public.firms."""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase/migrations/20261108165320_v2_research_claim.sql").read_text()
UNDO = (ROOT / "supabase/rollbacks/20261108165320_v2_research_claim.sql").read_text()
FN = (ROOT / "supabase/functions/research-ingest-v2/index.ts").read_text()
GUIDE = (ROOT / "docs/PAGE_DATA_GUIDE.md").read_text()
OLD_DOOR = (ROOT / "supabase/functions/research-ingest/index.ts").read_text()


def test_queue_is_v2_only_and_submit_is_untouched():
    low = SQL.lower()
    assert "create table if not exists public.v2_research_assignments" in low
    assert "references public.v2_firms(firm_id)" in low
    assert "public.firms" not in low
    assert "for update of q skip locked" in low
    assert "interval '6 hours'" in low
    assert "create or replace function public.v2_research_claim(p_key_id uuid)" in low
    assert "create or replace function public.v2_research_done(p_key_id uuid, p_firm_id bigint)" in low
    assert "create or replace function public.v2_research_submit" not in low
    assert "v2_firm_page" not in low
    assert "v2_firm_live" not in low
    assert "enable row level security" in low
    assert "revoke all on function public.v2_research_claim(uuid) from public, anon, authenticated" in low
    assert "grant execute on function public.v2_research_claim(uuid) to service_role" in low
    assert "to_regclass('public.v2_firms') is null" in low
    assert "drop table if exists public.v2_research_assignments" in UNDO.lower()
    assert "drop function if exists public.v2_research_claim(uuid)" in UNDO.lower()
    assert "drop function if exists public.v2_research_done(uuid, bigint)" in UNDO.lower()


def test_edge_routes_claim_and_done_without_changing_submit():
    assert 'body.action === "claim"' in FN
    assert 'body.action === "done"' in FN
    assert 'db.rpc("v2_research_claim"' in FN
    assert 'db.rpc("v2_research_done"' in FN
    assert 'db.rpc("v2_research_submit"' in FN
    assert 'db.rpc("v2_research_add_firm"' in FN
    claim = FN.index('body.action === "claim"')
    done = FN.index('body.action === "done"')
    submit = FN.index('db.rpc("v2_research_submit"')
    assert claim < done < submit
    assert "from(\"firms\")" not in FN
    assert "research_claim(" not in OLD_DOOR


def test_guide_mentions_claim_and_done_in_a_few_lines():
    start = GUIDE.index("- **A3.4**")
    end = GUIDE.index("<a id=\"a4\">", start)
    chunk = GUIDE[start:end].strip().splitlines()
    assert len(chunk) == 2
    text = " ".join(chunk)
    assert '{"action":"claim"}' in text
    assert '{"action":"done","firm_id":N}' in text
    assert "6 hours" in text
    assert "add_firm" in text and "submit" in text
