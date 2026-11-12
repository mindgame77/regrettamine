"""Search demand migrations stay split, and claim still freezes, expires, and skips locked rows."""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
ADD = (ROOT / "supabase/migrations/20261112180000_v2_search_demand_tables.sql").read_text()
JOB = (ROOT / "supabase/migrations/20261112190000_v2_search_demand_job.sql").read_text()
EDGE = (ROOT / "supabase/functions/ondemand-notify/index.ts").read_text()
COPY = (ROOT / "launch/copy.json").read_text()


def test_additive_migration_does_not_change_claim_or_schedule_cron():
    assert "public.v2_search_log" in ADD
    assert "public.v2_firm_watch" in ADD
    assert "demand_hidden boolean not null default false" in ADD
    assert "enable row level security" in ADD
    assert "revoke all on table public.v2_search_log from public, anon, authenticated" in ADD
    assert "cron.schedule" not in ADD
    assert "v2_research_claim" not in ADD
    assert "skipped" in ADD


def test_behavior_migration_orders_claim_by_priority_and_reuses_mail():
    assert "ORDER BY CASE q.priority WHEN 'top' THEN 0 ELSE 1 END, q.firm_id" in JOB
    assert "FOR UPDATE OF q SKIP LOCKED" in JOB
    assert "interval '6 hours'" in JOB
    assert "Key frozen" in JOB
    assert "select public.v2_search_demand_run()" in JOB
    assert "'0 */6 * * *'" in JOB
    assert "public.v2_search_go_live" in JOB
    assert "'search_live'" in JOB
    assert "pg_trgm" not in JOB
    assert 'case "search_live"' in EDGE
    assert "api.resend.com/emails" in EDGE


def test_investors_copy_is_the_requested_wording():
    assert "We don't have this firm yet. Leave your email and we'll let you know when we add it." in COPY
    assert "We'll notify you when we find this firm." in COPY
