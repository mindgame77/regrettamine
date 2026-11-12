"""Visitor search log: a tiny insert, no anon table access, and a private demand summary."""
import os
import pathlib

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase/migrations/20261112210000_v2_search_log.sql").read_text()
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()


def _body(text):
    return "\n".join(line for line in text.splitlines() if not line.strip().startswith("--")).lower()


def test_migration_is_a_small_write_path():
    low = _body(SQL)
    assert "create table public.v2_search_log" in low
    assert "id bigserial primary key" in low
    assert "term text not null" in low
    assert "term_norm text" in low
    assert "top_firm_id text" in low
    assert "anon_key text" in low
    assert "created_at timestamptz not null default now()" in low
    assert "enable row level security" in low
    assert "revoke all on table public.v2_search_log from public, anon, authenticated" in low
    assert "create index v2_search_log_created_at_idx on public.v2_search_log (created_at)" in low
    assert "create index v2_search_log_term_norm_idx on public.v2_search_log (term_norm)" in low
    assert low.count("create index") == 2
    assert "create or replace function public.log_search(" in low
    assert "security definer" in low
    assert "set search_path = public" in low
    assert "char_length(v_term) < 2" in low
    assert "left(" in low and ", 100)" in low
    assert "lower(v_term)" in low
    assert "< 30" in low
    assert "interval '1 hour'" in low
    assert "grant execute on function public.log_search(text, text, int, text, text) to anon" in low
    assert "to anon, authenticated" not in low.split("log_search")[-1]
    assert "create view public.search_demand" in low
    assert "security_invoker = true" in low
    assert "zero_results" in low
    assert "last_seen" in low
    assert "revoke all on table public.search_demand from public, anon, authenticated" in low
    assert "grant select" not in low
    assert "grant all" not in low


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
def test_log_search_caps_trims_rate_limits_and_hides_the_table():
    import psycopg

    conn = psycopg.connect(DATABASE_URL)
    conn.autocommit = False
    try:
        cur = conn.cursor()
        cur.execute("select to_regprocedure('public.log_search(text, text, int, text, text)')")
        if cur.fetchone()[0] is None:
            pytest.skip("log_search is not installed")
        cur.execute("select has_function_privilege('anon', 'public.log_search(text, text, integer, text, text)', 'execute')")
        assert cur.fetchone()[0] is True
        cur.execute("select has_function_privilege('authenticated', 'public.log_search(text, text, integer, text, text)', 'execute')")
        assert cur.fetchone()[0] is False

        cur.execute("select public.log_search('a', 'investors', 0, null, 'visitor-key-1')")
        cur.execute("select count(*) from public.v2_search_log where anon_key = 'visitor-key-1'")
        assert cur.fetchone()[0] == 0

        cur.execute(
            "select public.log_search(%s, ' investors ', 3, 'sequoia', 'visitor-key-1')",
            ("  Sequoia   Capital  " + ("x" * 120),),
        )
        cur.execute(
            """
            select term, term_norm, page, result_count, top_firm_id, char_length(term)
            from public.v2_search_log where anon_key = 'visitor-key-1'
            """
        )
        term, norm, page, count, top, n = cur.fetchone()
        assert n == 100
        assert term == ("Sequoia Capital " + ("x" * 120))[:100].replace("  ", " ")
        assert norm == term.lower()
        assert page == "investors"
        assert count == 3
        assert top == "sequoia"
        assert " " not in page

        cur.execute("select public.log_search('missing fund', 'home', 0, 'not a slug', 'visitor-key-1')")
        cur.execute(
            """
            select term_norm, searches, zero_results is not null, last_seen is not null
            from public.search_demand where term_norm = 'missing fund'
            """
        )
        row = cur.fetchone()
        assert row[0] == "missing fund"
        assert row[1] == 1
        assert row[2] is True and row[3] is True
        cur.execute("select top_firm_id from public.v2_search_log where term_norm = 'missing fund'")
        assert cur.fetchone()[0] is None

        cur.execute("select count(*) from public.v2_search_log where anon_key = 'rate-key-0001'")
        assert cur.fetchone()[0] == 0
        for i in range(31):
            cur.execute("select public.log_search(%s, 'home', 0, null, 'rate-key-0001')", (f"term {i:02d}",))
        cur.execute("select count(*) from public.v2_search_log where anon_key = 'rate-key-0001'")
        assert cur.fetchone()[0] == 30

        cur.execute("set role anon")
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            cur.execute("select * from public.v2_search_log")
        conn.rollback()
        cur = conn.cursor()
        cur.execute("select public.log_search('kept', 'home', 1, 'a16z', 'visitor-key-1')")
        cur.execute("set role anon")
        cur.execute("select public.log_search('from-anon', 'home', 0, null, 'visitor-key-9')")
        cur.execute("reset role")
        cur.execute("select count(*) from public.v2_search_log where term_norm = 'from-anon'")
        assert cur.fetchone()[0] == 1
        cur.execute("set role anon")
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            cur.execute("select * from public.search_demand")
    finally:
        conn.rollback()
        conn.close()
