"""bot_ingest can run every research-ingest RPC and cannot touch tables."""
import json
import os
import re
import secrets
from pathlib import Path
from urllib.parse import urlparse

import pytest

pytest.importorskip("psycopg")
import psycopg  # noqa: E402
from psycopg import sql  # noqa: E402

DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
ROOT = Path(__file__).resolve().parents[1]
INGEST = ROOT / "supabase" / "functions" / "research-ingest" / "index.ts"
ALLOW = {
    "ingest_auth",
    "research_status",
    "research_claim",
    "ondemand_job_info",
    "research_submit",
    "research_store_lps",
    "research_enrich",
    "firm_requests_list",
    "fact_add_source",
    "research_fail",
    "research_skip",
    "research_gaps_list",
    "research_claim_gaps",
    "ingest_trusted_domains",
    "ingest_bot_feedback",
    "ingest_needs_source",
}


def _j(v):
    return v if isinstance(v, (dict, list)) else json.loads(v)


def test_research_ingest_source_uses_the_limited_role():
    text = INGEST.read_text()
    assert "SUPABASE_SERVICE_ROLE_KEY" not in text
    assert "createClient" not in text
    assert ".from(" not in text
    assert "BOT_INGEST_DB_URL" in text
    called = set(re.findall(r"public\.([a-z0-9_]+)\(", text))
    assert called == ALLOW
    for name in ("billing-portal", "notify-checks", "ondemand-notify", "delete-account"):
        other = (ROOT / "supabase" / "functions" / name / "index.ts").read_text()
        assert "SUPABASE_SERVICE_ROLE_KEY" in other


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
def test_bot_ingest_role_can_run_every_ingest_action_and_nothing_else():
    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        role = cur.execute(
            "select rolcanlogin, rolsuper, rolbypassrls, rolinherit, rolcreatedb, rolcreaterole, "
            "rolreplication, rolconnlimit from pg_roles where rolname = 'bot_ingest'"
        ).fetchone()
        assert role == (True, False, False, False, False, False, False, 10)
        assert cur.execute("select rolpassword is null from pg_authid where rolname = 'bot_ingest'").fetchone()[0] is True
        config = cur.execute("select rolconfig from pg_roles where rolname = 'bot_ingest'").fetchone()[0]
        assert any(c.startswith("statement_timeout=") for c in config)
        assert any(c.startswith("lock_timeout=") for c in config)
        assert any(c.startswith("idle_in_transaction_session_timeout=") for c in config)
        assert cur.execute("select has_schema_privilege('bot_ingest', 'public', 'USAGE')").fetchone()[0] is True
        assert cur.execute("select has_schema_privilege('bot_ingest', 'public', 'CREATE')").fetchone()[0] is False
        assert cur.execute("select has_schema_privilege('bot_ingest', 'bots', 'USAGE')").fetchone()[0] is False

        granted = cur.execute(
            """
            select n.nspname, p.proname
              from pg_proc p
              join pg_namespace n on n.oid = p.pronamespace
             where n.nspname not in ('pg_catalog', 'information_schema')
               and n.nspname not like 'pg_%'
               and has_function_privilege('bot_ingest', p.oid, 'execute')
             order by 1, 2
            """
        ).fetchall()
        assert granted == [("public", name) for name in sorted(ALLOW)]

        tables = cur.execute(
            """
            select n.nspname || '.' || c.relname
              from pg_class c
              join pg_namespace n on n.oid = c.relnamespace
             where n.nspname in ('public', 'bots')
               and (
                 (c.relkind in ('r', 'v', 'm', 'p') and (
                    has_table_privilege('bot_ingest', c.oid, 'SELECT')
                    or has_table_privilege('bot_ingest', c.oid, 'INSERT')
                    or has_table_privilege('bot_ingest', c.oid, 'UPDATE')
                    or has_table_privilege('bot_ingest', c.oid, 'DELETE')))
                 or (c.relkind = 'S' and (
                    has_sequence_privilege('bot_ingest', c.oid, 'USAGE')
                    or has_sequence_privilege('bot_ingest', c.oid, 'SELECT')
                    or has_sequence_privilege('bot_ingest', c.oid, 'UPDATE')))
               )
            """
        ).fetchall()
        assert tables == []

        cur.execute("set local role bot_ingest")
        # Reads and no-op misses. These are the calls behind status, sources, feedback,
        # needs_source, gaps, firm_requests, submit, lps, add_source, fail, skip, enrich.
        status = _j(cur.execute("select research_status()").fetchone()[0])
        assert isinstance(status, dict)
        auth = _j(cur.execute("select ingest_auth(%s)", ("00" * 32,)).fetchone()[0])
        assert auth["ok"] is False and auth["error"] == "unauthorized"
        domains = _j(cur.execute("select ingest_trusted_domains()").fetchone()[0])
        assert isinstance(domains, list)
        feedback = _j(cur.execute("select ingest_bot_feedback('portal-night-bot')").fetchone()[0])
        assert isinstance(feedback, list)
        needing = _j(cur.execute("select ingest_needs_source(null, null, 1)").fetchone()[0])
        assert isinstance(needing, list)
        gaps = _j(cur.execute("select research_gaps_list(null, 1)").fetchone()[0])
        assert isinstance(gaps, list)
        assert cur.execute("select count(*) from firm_requests_list(1)").fetchone()[0] >= 0
        missing = _j(cur.execute(
            "select research_submit('zz-no-such-registry', 'zz-bot-ingest', '{}'::jsonb, 0, false, '[]'::jsonb)"
        ).fetchone()[0])
        assert missing["ok"] is False
        lps = _j(cur.execute(
            "select research_store_lps('zz-no-such-registry', 0, '[]'::jsonb, false)"
        ).fetchone()[0])
        assert lps["ok"] is False
        added = _j(cur.execute(
            "select fact_add_source(0, 'nope', 'https://example.com/page', null, 'zz-bot-ingest')"
        ).fetchone()[0])
        assert added["status"] == "error"
        failed = _j(cur.execute(
            "select research_fail('zz-no-such-registry', 'zz-bot-ingest', 'check')"
        ).fetchone()[0])
        assert failed["ok"] is False
        skipped = _j(cur.execute(
            "select research_skip('zz-no-such-registry', 'zz-bot-ingest', 'skip: check')"
        ).fetchone()[0])
        assert skipped["ok"] is False
        enrich = _j(cur.execute(
            "select research_enrich('not-the-enricher', '{\"slug\":\"zz-no-such-firm\"}'::jsonb)"
        ).fetchone()[0])
        assert "error" in enrich
        info = _j(cur.execute("select ondemand_job_info(array['zz-no-such-registry'])").fetchone()[0])
        assert info == {}
        # claim and claim_gap run for real and roll back with this transaction.
        cur.execute("select count(*) from research_claim('zz-bot-ingest-role', 1)")
        claimed = _j(cur.execute(
            "select research_claim_gaps('zz-bot-ingest-role', 'zz-no-such-registry')"
        ).fetchone()[0])
        assert claimed["ok"] is True and claimed["none_left"] is True
        for stmt in (
            "select 1 from firms",
            "select 1 from bots.ingest_keys",
            "insert into firms (slug, name) values ('zz-bot-ingest-nope', 'Nope')",
            "select edit_in_place('firms', '00000000-0000-0000-0000-000000000000'::uuid, "
            "'00000000-0000-0000-0000-000000000000'::uuid, '{}'::jsonb, 't', 't')",
        ):
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                cur.execute("savepoint nope")
                try:
                    cur.execute(stmt)
                finally:
                    cur.execute("rollback to savepoint nope")
        cur.execute("reset role")
        conn.rollback()

    pw = secrets.token_hex(16)
    admin = psycopg.connect(DATABASE_URL)
    admin.autocommit = True
    try:
        try:
            admin.execute(sql.SQL("alter role bot_ingest password {}").format(sql.Literal(pw)))
        except Exception:
            raise AssertionError("could not set a temporary login password for the role check") from None
        parts = urlparse(DATABASE_URL)
        with psycopg.connect(
            host=parts.hostname,
            port=parts.port or 5432,
            dbname=parts.path.lstrip("/"),
            user="bot_ingest",
            password=pw,
        ) as door, door.cursor() as cur:
            assert cur.execute("select current_user").fetchone()[0] == "bot_ingest"
            statement_timeout, lock_timeout = cur.execute(
                "select current_setting('statement_timeout'), current_setting('lock_timeout')"
            ).fetchone()
            assert statement_timeout in ("30s", "30000ms")
            assert lock_timeout in ("5s", "5000ms")
            assert isinstance(_j(cur.execute("select research_status()").fetchone()[0]), dict)
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                cur.execute("select 1 from firms")
    finally:
        admin.close()
        with psycopg.connect(DATABASE_URL) as cleanup:
            cleanup.autocommit = True
            cleanup.execute("alter role bot_ingest password null")
            assert cleanup.execute(
                "select rolpassword is null from pg_authid where rolname = 'bot_ingest'"
            ).fetchone()[0] is True
