"""Bot holding area lives in the bots schema. Uploads do not write firm rows. bots.search_log was removed (search lists stay in the payload)."""
import json
import os
import uuid

import pytest

pytest.importorskip("psycopg")
import psycopg  # noqa: E402

DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")


def _j(v):
    return v if isinstance(v, (dict, list)) else json.loads(v)


def test_bot_upload_stays_in_bots_and_site_rpcs_still_work():
    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        assert cur.execute("select to_regclass('public.research_submissions')").fetchone()[0] is None
        assert cur.execute("select to_regclass('bots.research_submissions')").fetchone()[0] is not None
        assert cur.execute("select to_regclass('public.research_queue')").fetchone()[0] is not None
        assert cur.execute("select to_regclass('public.facts_needing_source')").fetchone()[0] is not None
        assert cur.execute("select to_regclass('bots.search_log')").fetchone()[0] is None
        assert cur.execute("select to_regclass('bots.search_log_current')").fetchone()[0] is None

        cur.execute("insert into research_queue (registry_id, name, priority, status, claimed_by) "
                    "values ('zz-bot-hold', 'ZZ Bot Hold', 5, 'claimed', 'zz-bot')")
        firms_before = cur.execute("select count(*) from firms where registry_id = 'zz-bot-hold'").fetchone()[0]
        payload = {"search_log": [{"query_id": "q", "tool": "web", "query": "zz bot hold"}], "firm": {"generated_at": "2026-10-01"}}
        got = _j(cur.execute(
            "select research_submit('zz-bot-hold', 'zz-bot', %s, 0, true, '[]'::jsonb)",
            (json.dumps(payload),)).fetchone()[0])
        assert got["ok"] is True
        row = cur.execute("select payload from bots.research_submissions where registry_id = 'zz-bot-hold'").fetchone()
        assert row is not None and _j(row[0])["search_log"][0]["query"] == "zz bot hold"
        assert cur.execute("select count(*) from firms where registry_id = 'zz-bot-hold'").fetchone()[0] == firms_before == 0
        fid = cur.execute(
            "insert into firms (slug, name, published, data_status, registry_id, indexable) "
            "values ('zz-bot-hold', 'ZZ Bot Hold', true, 'real', 'zz-bot-hold', false) returning id").fetchone()[0]
        pub = _j(cur.execute("select _promote_submissions(%s)", (fid,)).fetchone()[0])
        assert pub["closed"] is True and pub["submission_id"] is None and pub["facts"] == 0
        assert cur.execute("select report_date from firms where id = %s", (fid,)).fetchone()[0] is None
        assert cur.execute("select indexable from firms where id = %s", (fid,)).fetchone()[0] is False

        # CI seed has a16z. Y Combinator is created here when the database has no gold row.
        # The transaction rolls back, so this does not insert a firm for real.
        for slug, name, short in (("y-combinator", "Y Combinator", "YC"), ("a16z", "Andreessen Horowitz", "a16z")):
            cur.execute(
                "insert into firms (slug, name, short_name, published, data_status, indexable) "
                "values (%s, %s, %s, true, 'real', true) "
                "on conflict (slug) do update set published = true, data_status = 'real', "
                "deleted_at = null, is_test = false, indexable = true",
                (slug, name, short))
            page = _j(cur.execute("select firm_page(%s, %s, false)", (slug, str(uuid.uuid4()))).fetchone()[0])
            assert page["status"] == "ok", slug
            status = _j(cur.execute("select firm_check_status(%s)", (slug,)).fetchone()[0])
            assert status["status"] == "ok", slug
        sug = _j(cur.execute("select firm_suggest('y com')").fetchone()[0])
        assert any(r["slug"] == "y-combinator" for r in sug)
        sug = _j(cur.execute("select firm_suggest('a16z')").fetchone()[0])
        assert any(r["slug"] == "a16z" for r in sug)

        cur.execute("savepoint botw")
        try:
            cur.execute("set local role bot_writer")
            cur.execute("insert into public.firms (slug, name) values ('zz-bot-writer-nope', 'Nope')")
            raise AssertionError("bot_writer wrote public.firms")
        except psycopg.errors.InsufficientPrivilege:
            cur.execute("rollback to savepoint botw")
        cur.execute("set local role bot_writer")
        cur.execute("select research_claim('zz-bot-writer', 1)")
        cur.execute("reset role")

        cur.execute("select bots.apply_limits()")
        statement_timeout, lock_timeout = cur.execute(
            "select current_setting('statement_timeout'), current_setting('lock_timeout')").fetchone()
        assert statement_timeout in ("30s", "30000ms")
        assert lock_timeout in ("5s", "5000ms")
        assert "bots.apply_limits" in cur.execute(
            "select prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace "
            "where n.nspname = 'public' and p.proname = 'research_submit'").fetchone()[0]
        limit, config = cur.execute(
            "select rolconnlimit, rolconfig from pg_roles where rolname = 'bot_writer'").fetchone()
        assert limit == 10
        assert any(c.startswith("statement_timeout=") for c in config)
        assert any(c.startswith("lock_timeout=") for c in config)

        assert cur.execute("select to_regprocedure('bots.purge_old_search_log()')").fetchone()[0] is None
        if cur.execute("select to_regclass('cron.job')").fetchone()[0] is not None:
            assert cur.execute("select count(*) from cron.job where jobname = 'bots-search-log-retention'").fetchone()[0] == 0

        friend = cur.execute(
            "select active from bots.ingest_keys where name = 'external-friend-2026-10-23'").fetchone()
        if friend is not None:
            assert friend[0] is False
        conn.rollback()
