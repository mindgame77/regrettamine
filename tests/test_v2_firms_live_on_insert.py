"""A v2 firm is live as soon as it is added. Existing live rows stay. public.firms is not touched."""
import os
import pathlib
import shutil
import subprocess

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase/migrations/20261108180000_v2_firms_live_on_insert.sql").read_text()
UNDO = (ROOT / "supabase/rollbacks/20261108180000_v2_firms_live_on_insert.sql").read_text()
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()


def _body(text):
    lines = [line for line in text.splitlines() if not line.strip().startswith("--")]
    return "\n".join(lines).lower()


def test_migration_inserts_live_rows_and_leaves_everything_else():
    low = _body(SQL)
    assert "create or replace function public.v2_firm_live_on_insert()" in low
    assert "after insert on public.v2_firms" in low
    assert "insert into public.v2_firm_live (firm_id, slug)" in low
    assert "on conflict (firm_id) do nothing" in low
    assert "not exists" in low
    assert "security definer" in low
    assert "set search_path = public" in low
    assert "revoke all on function public.v2_firm_live_on_insert() from public, anon, authenticated" in low
    assert "grant execute on function public.v2_firm_live_on_insert() to service_role" in low
    assert "to_regclass('public.v2_firms') is null" in low
    assert "public.firms" not in low
    assert "delete " not in low
    assert "truncate " not in low
    assert "update " not in low
    assert "drop table" not in low
    undo = _body(UNDO)
    assert "drop trigger if exists v2_firms_live_on_insert" in undo
    assert "drop function if exists public.v2_firm_live_on_insert()" in undo
    assert "public.firms" not in undo
    assert "delete " not in undo
    assert "truncate " not in undo


@pytest.mark.skipif(not shutil.which("node"), reason="node not installed")
def test_empty_firm_page_paints():
    r = subprocess.run(
        ["node", "--test", "tests/empty_firm_page.test.mjs"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, r.stdout[-3000:] + r.stderr[-2000:]


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
def test_trigger_and_backfill_on_a_throwaway_schema():
    import psycopg

    conn = psycopg.connect(DATABASE_URL)
    try:
        cur = conn.cursor()
        firms_before = cur.execute("select count(*) from public.firms").fetchone()[0]
        cur.execute(
            """
            create table public.v2_firms (
              firm_id bigint generated always as identity primary key,
              slug varchar unique,
              display_name varchar not null,
              archived boolean not null default false
            )
            """
        )
        cur.execute(
            """
            create table public.v2_firm_live (
              firm_id bigint primary key references public.v2_firms(firm_id),
              slug text not null unique,
              live_since timestamptz not null default now(),
              note text
            )
            """
        )
        cur.execute(
            "insert into public.v2_firms (slug, display_name) values (%s, %s)",
            ("a16z", "Andreessen Horowitz"),
        )
        cur.execute(
            """
            insert into public.v2_firm_live (firm_id, slug, note, live_since)
            select firm_id, 'a16z', 'Alex start', '2026-11-04 01:17:38+00'
            from public.v2_firms where slug = 'a16z'
            """
        )
        cur.execute(
            "insert into public.v2_firms (slug, display_name, archived) values (%s, %s, true)",
            ("old-fund", "Old Fund"),
        )
        cur.execute(
            "insert into public.v2_firms (slug, display_name) values (%s, %s), (%s, %s)",
            ("  Accel  ", "Accel", "founders-fund", "Founders Fund"),
        )
        cur.execute("insert into public.v2_firms (display_name) values (%s)", ("No Slug",))
        cur.execute(SQL)
        kept = cur.execute(
            """
            select l.slug, l.note, l.live_since
            from public.v2_firm_live l
            join public.v2_firms f on f.firm_id = l.firm_id
            where f.slug = 'a16z'
            """
        ).fetchone()
        assert kept[0] == "a16z"
        assert kept[1] == "Alex start"
        assert str(kept[2]).startswith("2026-11-04")
        live = dict(
            cur.execute(
                """
                select f.slug, l.slug
                from public.v2_firms f
                left join public.v2_firm_live l on l.firm_id = f.firm_id
                """
            ).fetchall()
        )
        assert live["  Accel  "] == "accel"
        assert live["founders-fund"] == "founders-fund"
        assert live["old-fund"] == "old-fund"
        assert live[None] is None
        cur.execute(
            "insert into public.v2_firms (slug, display_name) values (%s, %s) returning firm_id",
            ("Greenoaks", "Greenoaks"),
        )
        new_id = cur.fetchone()[0]
        added = cur.execute(
            "select slug, note from public.v2_firm_live where firm_id = %s",
            (new_id,),
        ).fetchone()
        assert added == ("greenoaks", None)
        cur.execute("insert into public.v2_firms (display_name) values (%s)", ("Also Blank",))
        assert cur.execute(
            """
            select count(*) from public.v2_firm_live l
            join public.v2_firms f on f.firm_id = l.firm_id
            where f.display_name = 'Also Blank'
            """
        ).fetchone()[0] == 0
        cur.execute(SQL)
        assert cur.execute("select count(*) from public.v2_firm_live where firm_id = %s", (new_id,)).fetchone()[0] == 1
        assert cur.execute(
            "select note from public.v2_firm_live where slug = 'a16z'"
        ).fetchone()[0] == "Alex start"
        assert cur.execute("select count(*) from public.firms").fetchone()[0] == firms_before
        assert cur.execute(
            "select has_function_privilege('anon', 'public.v2_firm_live_on_insert()', 'execute')"
        ).fetchone()[0] is False
        assert cur.execute(
            "select has_function_privilege('service_role', 'public.v2_firm_live_on_insert()', 'execute')"
        ).fetchone()[0] is True
        cur.execute(UNDO)
        assert cur.execute(
            "select count(*) from pg_trigger where tgname = 'v2_firms_live_on_insert'"
        ).fetchone()[0] == 0
        assert cur.execute("select count(*) from public.v2_firm_live").fetchone()[0] == 5
        assert cur.execute("select count(*) from public.firms").fetchone()[0] == firms_before
    finally:
        conn.rollback()
        conn.close()
