"""A4.6 (Alex, 2026-10-28): the entry-check result is visible only to the bot that sent the upload; never shown to
site users. research-ingest returns it on upload and through action my_results. The bot comes from its ingest key
(bots.ingest_keys.bot_id), never from bot_id in the request. Each database test runs in a rolled-back transaction."""
import json
import os
import pathlib
import shutil
import subprocess
import uuid

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIG = (ROOT / "supabase/migrations/20261029093000_bot_own_results.sql").read_text()
RB = (ROOT / "supabase/rollbacks/20261029093000_bot_own_results.sql").read_text()
FN = (ROOT / "supabase/functions/research-ingest/index.ts").read_text()
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()


def test_migration_is_additive_and_server_only():
    low = MIG.lower()
    for bad in ("alter table", "drop ", "create policy", "create trigger", "research_submit(", "entry_check_trg", "firm_check"):
        assert bad not in low, bad
    for fn in ("public.research_entry_result(bigint)", "public.research_my_results(uuid, int, int)"):
        assert f"revoke all on function {fn} from public, anon, authenticated;" in MIG
        assert f"grant execute on function {fn} to service_role;" in MIG
    assert low.count("security definer set search_path = bots, public") == 2
    assert "k.active" in MIG and "k.bot_id" in MIG and "limit n" in MIG


def test_rollback_drops_both_and_keeps_old_function_source():
    assert "drop function if exists public.research_my_results(uuid, int, int);" in RB
    assert "drop function if exists public.research_entry_result(bigint);" in RB
    old = (ROOT / "supabase/rollbacks/20261029093000_research_ingest_v30.ts").read_text()
    assert "research_my_results" not in old and "entry_check" not in old


def test_edge_function_uses_key_not_body_bot():
    i = FN.index('case "my_results"')
    block = FN[i:FN.index("default:", i)]
    assert "p_key: keyId" in block and "body.bot_id" not in block.split("\n", 2)[2]
    assert "bot," not in block and "p_bot" not in block
    assert FN.count("...(await entryOf(data.submission_id))") >= 2


def test_docs_a4_6():
    guide = (ROOT / "docs/PAGE_DATA_GUIDE.md").read_text()
    assert "visible only to the bot that sent it; never shown to site users" in guide.lower()
    idx = (ROOT / "docs/rules_index.csv").read_bytes()
    line = [l for l in idx.split(b"\n") if l.startswith(b"A4.6,")]
    assert len(line) == 1 and b"visible only to the bot that sent it; never shown to site users" in line[0].lower()


def test_deno_handler_tests():
    deno = shutil.which("deno") or str(pathlib.Path.home() / ".deno/bin/deno")
    if not pathlib.Path(deno).exists():
        pytest.skip("deno is not installed")
    r = subprocess.run([deno, "test", "-A", "--no-check", "tests/research_ingest_results.test.ts"], cwd=ROOT,
                       capture_output=True, text=True, timeout=300)
    assert r.returncode == 0, r.stdout[-3000:] + r.stderr[-3000:]


@pytest.fixture()
def cur():
    if not DATABASE_URL:
        pytest.skip("DATABASE_URL is not set")
    import psycopg
    with psycopg.connect(DATABASE_URL) as c:
        if c.execute("select to_regprocedure('public.research_my_results(uuid,int,int)')").fetchone()[0] is None:
            pytest.skip("bot own results migration not applied")
        try:
            yield c
        finally:
            c.rollback()


def key(c, bot, active=True):
    k = uuid.uuid4()
    c.execute("insert into bots.ingest_keys (id, name, key_hash, active, bot_id) values (%s, %s, %s, %s, %s)",
              (k, f"test-{k}", uuid.uuid4().hex + uuid.uuid4().hex, active, bot))
    return k


def sub(c, bot, rid="vc-test-own-1", age="0 days"):
    c.execute("insert into research_queue (registry_id, name, priority, status) values (%s, 'Own Test', 999999, 'submitted') "
              "on conflict (registry_id) do nothing", (rid,))
    return c.execute("insert into bots.research_submissions (registry_id, bot_id, payload, record_count, valid, received_at) "
                     "values (%s, %s, '{}'::jsonb, 0, false, now() - %s::interval) returning id", (rid, bot, age)).fetchone()[0]


def mine(c, k, days=30, limit=30):
    return c.execute("select public.research_my_results(%s, %s, %s)", (k, days, limit)).fetchone()[0]


def test_bot_sees_only_its_own_rows(cur):
    ka, kb = key(cur, "zz-own-a"), key(cur, "zz-own-b")
    a1, b1 = sub(cur, "zz-own-a"), sub(cur, "zz-own-b")
    ra, rb = mine(cur, ka), mine(cur, kb)
    assert ra["bot_id"] == "zz-own-a" and [r["submission_id"] for r in ra["results"]] == [a1]
    assert [r["submission_id"] for r in rb["results"]] == [b1]
    assert set(ra["results"][0]) == {"submission_id", "registry_id", "received_at", "entry_check", "entry_notes", "entry_check_at"}


def test_window_and_cap(cur):
    k = key(cur, "zz-own-c")
    sub(cur, "zz-own-c", age="31 days")
    ids = [sub(cur, "zz-own-c") for _ in range(32)]
    r = mine(cur, k, 99, 99)
    assert r["days"] == 30 and len(r["results"]) == 30 and r["results"][0]["submission_id"] == ids[-1]


def test_unlinked_or_inactive_key_gets_nothing(cur):
    sub(cur, "zz-own-d")
    for k in (key(cur, None), key(cur, "zz-own-d", active=False), uuid.uuid4()):
        r = mine(cur, k)
        assert r["ok"] is False and "results" not in r


def test_entry_result_shape(cur):
    s = sub(cur, "zz-own-e")
    r = cur.execute("select public.research_entry_result(%s)", (s,)).fetchone()[0]
    assert set(r) == {"entry_check", "entry_notes", "entry_check_at"}
    assert cur.execute("select public.research_entry_result(-1)").fetchone()[0] == {"entry_check": None, "entry_notes": None, "entry_check_at": None}


@pytest.mark.parametrize("role", ["anon", "authenticated"])
def test_site_roles_read_nothing(cur, role):
    for sig in ("public.research_entry_result(bigint)", "public.research_my_results(uuid,int,int)"):
        assert cur.execute("select has_function_privilege(%s, %s, 'execute')", (role, sig)).fetchone()[0] is False
    for t in ("bots.research_submissions", "bots.ingest_keys"):
        assert cur.execute("select has_table_privilege(%s, %s, 'select')", (role, t)).fetchone()[0] is False
