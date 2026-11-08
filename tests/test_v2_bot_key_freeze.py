"""A key freezes at 100 rejections for one firm. The hourly firm cap stays."""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase/migrations/20261108193000_v2_bot_key_freeze_per_firm.sql").read_text()
UNDO = (ROOT / "supabase/rollbacks/20261108193000_v2_bot_key_freeze_per_firm.sql").read_text()
GUIDE = (ROOT / "docs/PAGE_DATA_GUIDE.md").read_text()
DOOR = (ROOT / "supabase/functions/research-ingest-v2/index.ts").read_text()


def _block(text, marker):
    start = text.index(marker) + len(marker)
    end = text.index(marker, start)
    return text[start:end]


def test_only_the_rejection_freeze_changes():
    new = _block(SQL, "$new$")
    old = _block(SQL, "$old$")
    assert "GROUP BY coalesce(firm_id::text, payload->>'firm_ref')" in new
    assert "max(firm_rej)" in new and "AS firm_rej" in new
    assert "max(n)" not in new and " AS n " not in new
    assert "rej_today >= 100 THEN" in new
    assert "rejections today for one firm" in new
    assert "date_trunc('day', now() AT TIME ZONE 'America/Los_Angeles')" in new
    hour = "SELECT count(DISTINCT coalesce(firm_id::text, payload->>'firm_ref')) INTO firms_hour FROM public.v2_research_submissions\n    WHERE bot_key_id = bk.bot_key_id AND received_at > now() - interval '1 hour';"
    assert hour in new and hour in old
    assert "firms_hour > 100 THEN format('%s firms in the last hour', firms_hour)" in new
    assert "rej_today >= 10 THEN" not in new
    assert "rej_today >= 10 THEN" in old
    assert "to_regprocedure('public.v2_research_submit(uuid,jsonb,boolean)') is null" in SQL
    assert "raise notice 'v2 schema missing, skipped'" in SQL
    assert "UPDATE public.v2_bot_keys SET frozen=false, freeze_date=NULL, freeze_reason=NULL WHERE bot_key_id=322;" in SQL
    assert "create or replace function public.v2_research_submit" not in SQL.lower()
    assert "create table" not in SQL.lower()
    assert "v2_firm_page" not in SQL


def test_a_database_that_already_used_the_name_n_is_renamed():
    fix = (ROOT / "supabase/migrations/20261108195000_v2_bot_key_freeze_count_name.sql").read_text()
    assert "AS firm_rej" in _block(fix, "$new$")
    assert "max(n)" in _block(fix, "$old$")
    assert "firms_hour > 100" in fix
    assert "bot_key_id=322" not in fix
    assert "to_regprocedure('public.v2_research_submit(uuid,jsonb,boolean)') is null" in fix


def test_undo_restores_the_all_firms_count_and_leaves_the_key():
    undone = _block(UNDO, "$new$")
    assert "rej_today >= 10 THEN" in undone
    assert "SELECT count(*) INTO rej_today" in undone
    assert "GROUP BY" not in undone
    assert "firms_hour > 100" in undone
    assert "bot_key_id=322" not in UNDO
    assert "bot_key_id = 322" not in UNDO


def test_guide_states_the_per_firm_limit_and_keeps_the_hour_rule():
    line = [ln for ln in GUIDE.splitlines() if ln.startswith("- **A4.6**")]
    assert len(line) == 1
    assert "100 rejections for one firm in a Pacific day" in line[0]
    assert "More than 100 distinct firms in an hour still freezes that key." in line[0]
    assert "visible only to the bot that sent it; never shown to site users" in line[0]
    assert "starts at 100" in GUIDE
    assert "three times the limit" in GUIDE
    assert "There is no second setting" in GUIDE
    assert "dry_run" in DOOR
    assert "100 rejections" not in DOOR
