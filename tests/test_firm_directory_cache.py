"""Investors directory cache: one row, anon reads the RPC, not the table."""
import os
import pathlib
import shutil
import subprocess

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIG = (ROOT / "supabase/migrations/20261112190000_firm_directory_cache.sql").read_text(encoding="utf-8")
UNDO = (ROOT / "supabase/rollbacks/20261112190000_firm_directory_cache.sql").read_text(encoding="utf-8")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()


def test_migration_adds_the_cache_and_leaves_firm_directory_alone():
    assert "create table public.v2_firm_directory_cache" in MIG
    assert "id int primary key default 1 check (id = 1)" in MIG
    assert "payload jsonb not null" in MIG
    assert "built_at timestamptz not null" in MIG
    assert "enable row level security" in MIG
    assert "revoke all on table public.v2_firm_directory_cache from public, anon, authenticated" in MIG
    assert "create or replace function public.refresh_firm_directory_cache()" in MIG
    assert "security definer" in MIG
    assert "set statement_timeout to '60s'" in MIG
    assert "public.firm_directory()" in MIG
    assert "create or replace function public.firm_directory(" not in MIG
    assert "drop function" not in MIG.lower()
    assert "drop table" not in MIG.lower()
    assert "grant execute on function public.firm_directory_cached() to anon, authenticated" in MIG
    assert "revoke all on function public.refresh_firm_directory_cache() from public, anon, authenticated" in MIG
    assert "'firm-directory-cache'" in MIG
    assert "'0 * * * *'" in MIG
    assert "select public.refresh_firm_directory_cache();" in MIG
    assert "pg_cron is not installed" in MIG


def test_rollback_unschedules_the_job_and_drops_only_the_cache():
    assert "cron.unschedule('firm-directory-cache')" in UNDO
    assert "drop function if exists public.firm_directory_cached()" in UNDO
    assert "drop function if exists public.refresh_firm_directory_cache()" in UNDO
    assert "drop table if exists public.v2_firm_directory_cache" in UNDO
    assert "drop function if exists public.firm_directory()" not in UNDO
    assert "drop function public.firm_directory()" not in UNDO
    assert "delete from" not in UNDO.lower()


@pytest.mark.skipif(not shutil.which("node"), reason="node not installed")
def test_investors_page_tries_the_cache_then_the_live_rpc():
    r = subprocess.run(
        ["node", "--test", "tests/firm_directory_cache.test.mjs"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, r.stdout[-3000:] + r.stderr[-2000:]


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
def test_anon_reads_the_cached_rpc_and_cannot_touch_the_table_or_refresh():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn:
        conn.execute("begin")
        try:
            locked = conn.execute(
                """
                select c.relrowsecurity,
                       (select count(*) from pg_policy p where p.polrelid = c.oid)
                  from pg_class c
                  join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname = 'public' and c.relname = 'v2_firm_directory_cache'
                """
            ).fetchone()
            assert locked == (True, 0)
            for role in ("anon", "authenticated"):
                assert conn.execute(
                    "select has_table_privilege(%s, 'public.v2_firm_directory_cache', 'select')",
                    (role,),
                ).fetchone()[0] is False
                assert conn.execute(
                    "select has_function_privilege(%s, 'public.refresh_firm_directory_cache()', 'execute')",
                    (role,),
                ).fetchone()[0] is False
                assert conn.execute(
                    "select has_function_privilege(%s, 'public.firm_directory_cached()', 'execute')",
                    (role,),
                ).fetchone()[0] is True
            cfg = conn.execute(
                "select proconfig from pg_proc where oid = 'public.refresh_firm_directory_cache()'::regprocedure"
            ).fetchone()[0]
            assert any(item.startswith("search_path=") for item in cfg)
            assert any(item.startswith("statement_timeout=") and "60" in item for item in cfg)

            conn.execute("delete from public.v2_firm_directory_cache")
            assert conn.execute("select public.firm_directory_cached()").fetchone()[0] is None

            if not conn.execute("select to_regprocedure('public.firm_directory()') is not null").fetchone()[0]:
                conn.execute(
                    """
                    create function public.firm_directory()
                    returns json
                    language sql
                    stable
                    security definer
                    set search_path to 'public', 'pg_temp'
                    as $$ select '[{"slug":"a16z","name":"Andreessen Horowitz"}]'::json $$
                    """
                )
            conn.execute("select public.refresh_firm_directory_cache()")
            live = conn.execute("select public.firm_directory()::jsonb").fetchone()[0]
            stored, built = conn.execute(
                "select payload, built_at is not null from public.v2_firm_directory_cache where id = 1"
            ).fetchone()
            assert stored == live
            assert built is True
            cached = conn.execute("select public.firm_directory_cached()").fetchone()[0]
            assert cached["payload"] == live
            assert cached["built_at"]

            conn.execute("savepoint bad_id")
            with pytest.raises(psycopg.errors.CheckViolation):
                conn.execute(
                    "insert into public.v2_firm_directory_cache (id, payload, built_at) values (2, '[]'::jsonb, now())"
                )
            conn.execute("rollback to savepoint bad_id")

            conn.execute("set role anon")
            conn.execute("savepoint anon_table")
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                conn.execute("select payload from public.v2_firm_directory_cache")
            conn.execute("rollback to savepoint anon_table")
            conn.execute("savepoint anon_refresh")
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                conn.execute("select public.refresh_firm_directory_cache()")
            conn.execute("rollback to savepoint anon_refresh")
            seen = conn.execute("select public.firm_directory_cached()").fetchone()[0]
            assert seen["payload"] == live
            conn.execute("reset role")
        finally:
            conn.execute("rollback")
