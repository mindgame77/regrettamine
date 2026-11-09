"""Pickup for an already registered research key.

The bot applies with a proof. The owner approves once. The key is returned once.
Local database only: set BOT_KEY_TEST_URL to a localhost database. Hosted Supabase is refused.
"""
import hashlib
import importlib.util
import json
import os
import pathlib
import secrets

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIG = (ROOT / "supabase/migrations/20261109020000_bot_key_pickup.sql").read_text()
UNDO = (ROOT / "supabase/rollbacks/20261109020000_bot_key_pickup.sql").read_text()
DOOR = (ROOT / "supabase/functions/bot-key-apply/index.ts").read_text()
CFG = (ROOT / "supabase/config.toml").read_text()
GUIDE = (ROOT / "docs/BOT_KEYS.md").read_text()
LOCAL = os.environ.get("BOT_KEY_TEST_URL", "").strip()

spec = importlib.util.spec_from_file_location("new_bot_key", ROOT / "scripts/new_bot_key.py")
nbk = importlib.util.module_from_spec(spec)
spec.loader.exec_module(nbk)

SCHEMA = """
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'bot_writer') then create role bot_writer nologin; end if;
end $$;
create schema if not exists bots;
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create table if not exists bots.ingest_keys (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  key_hash text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  rate_limit_per_min int not null default 30,
  bot_id text
);
grant usage on schema bots to bot_writer, service_role, anon, authenticated;
grant select, insert, update, delete on bots.ingest_keys to bot_writer, service_role;
alter table bots.ingest_keys enable row level security;
drop policy if exists bot_writer_all on bots.ingest_keys;
create policy bot_writer_all on bots.ingest_keys for all to bot_writer using (true) with check (true);
"""


def _obj(value):
    if isinstance(value, str):
        return json.loads(value)
    return value


def _local_ok():
    if not LOCAL:
        return False
    if "supabase" in LOCAL or "sxxgvkdwgiouyqciztec" in LOCAL:
        return False
    return LOCAL.startswith("dbname=") or "localhost" in LOCAL or "127.0.0.1" in LOCAL


@pytest.fixture(scope="session")
def migrated():
    if not _local_ok():
        pytest.skip("BOT_KEY_TEST_URL must be a local database")
    import psycopg
    with psycopg.connect(LOCAL, autocommit=True) as conn:
        conn.execute(SCHEMA)
        for sig in (
            "public.pending_bot_key_pickups()",
            "public.clear_bot_key_pickup(text)",
            "public.approve_bot_key_pickup(text)",
            "public.bot_key_apply(text, text)",
            "public.seal_bot_key_pickup(text, text)",
        ):
            conn.execute(f"drop function if exists {sig}")
        conn.execute("drop table if exists bots.bot_key_pickup")
        conn.execute(MIG)
    yield LOCAL


@pytest.fixture()
def cur(migrated):
    import psycopg
    from psycopg.types.json import set_json_loads
    with psycopg.connect(migrated) as conn:
        set_json_loads(json.loads, conn)
        try:
            yield conn
        finally:
            conn.rollback()


def add_key(cur, bot, raw, active=True, rate=30, used="2026-11-01 00:00+00"):
    digest = hashlib.sha256(raw.encode()).hexdigest()
    cur.execute(
        """insert into bots.ingest_keys (name, key_hash, active, bot_id, rate_limit_per_min, last_used_at)
           values (%s, %s, %s, %s, %s, %s)""",
        (f"bot-{bot}", digest, active, bot, rate, used),
    )
    return digest


def identity(cur, bot):
    return cur.execute(
        """select id::text, name, key_hash, active, rate_limit_per_min, bot_id, last_used_at
             from bots.ingest_keys where bot_id = %s""",
        (bot,),
    ).fetchone()


def call(cur, sql, args=()):
    return _obj(cur.execute(sql, args).fetchone()[0])


def seal(cur, bot, raw):
    return call(cur, "select public.seal_bot_key_pickup(%s, %s)", (bot, raw))


def apply(cur, bot, proof):
    digest = hashlib.sha256(proof.encode()).hexdigest()
    return call(cur, "select public.bot_key_apply(%s, %s)", (bot, digest)), digest


def dumped(rows):
    return json.dumps(rows, default=str)


def test_migration_is_pickup_only():
    low = MIG.lower()
    assert "grant execute on function public.bot_key_apply(text, text) to anon" not in low
    assert "grant execute on function public.bot_key_apply(text, text) to authenticated" not in low
    assert "grant execute on function public.bot_key_apply(text, text) to bot_writer" not in low
    assert "grant execute on function public.bot_key_apply(text, text) to service_role;" in MIG
    assert "revoke all on function public.bot_key_apply(text, text) from public, anon, authenticated;" in MIG
    assert "security definer set search_path = bots, public" in low
    assert "alter table bots.ingest_keys" not in low
    assert "set key_hash" not in low
    assert "set active" not in low
    assert "set rate_limit" not in low
    assert "create table bots.bot_key_pickup" in MIG
    assert "revoke all on table bots.bot_key_pickup from public, anon, authenticated, bot_writer, service_role;" in MIG
    for secret in ("41196041-eafb-400d-9b7a-0eeda350f73a", "15ac08c7-9c9f-4c1b-9397-d759d8eb8f00", "rgk_"):
        assert secret not in MIG
    assert "drop table if exists bots.bot_key_pickup;" in UNDO
    assert "ingest_keys" not in UNDO.split("bots.ingest_keys is not changed.", 1)[-1].lower()
    assert "delete from" not in UNDO.lower()


def test_door_redacts_and_rejects_url_secrets():
    assert 'console.log(JSON.stringify({ evt: "bot_key_apply", bot_id: bot || null, status, code }))' in DOOR
    assert "searchParams" in DOOR
    assert "p_proof_hash: proofHash" in DOOR
    assert "p_proof:" not in DOOR
    for banned in ("console.log(raw", "console.log(proof", "console.log(body", "console.log(data", "error.message"):
        assert banned not in DOOR
    assert 'Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")' in DOOR
    assert "service_role" not in DOOR.split("console.log", 1)[1]
    assert "Cache-Control" in DOOR and "no-store" in DOOR
    assert "data.status === \"delivered\"" in DOOR
    assert "[functions.bot-key-apply]" in CFG and "verify_jwt = false" in CFG.split("[functions.bot-key-apply]")[1]
    assert "https://sxxgvkdwgiouyqciztec.supabase.co/functions/v1/bot-key-apply" in GUIDE
    assert "portal-night-bot" in GUIDE and "add_firm" in GUIDE
    assert "rgk_" not in GUIDE


def test_seal_command_never_prints_key(tmp_path, capsys, monkeypatch):
    monkeypatch.setattr(nbk, "KEY_DIR", str(tmp_path))
    path, _ = nbk.write_key("zz-seal-bot", str(tmp_path))
    raw = pathlib.Path(path).read_text().strip()
    seen = {}

    class Conn:
        def execute(self, sql, params=None):
            if params:
                seen["params"] = params
            class Cur:
                def fetchone(_self):
                    if "to_regprocedure" in sql:
                        return ("public.seal_bot_key_pickup(text,text)",)
                    return ({"ok": True, "bot_id": "zz-seal-bot", "status": "sealed", "key": raw, "error": raw},)
            return Cur()
        def __enter__(self):
            return self
        def __exit__(self, *args):
            return False

    monkeypatch.setattr(nbk, "connect_db", lambda url: Conn())
    monkeypatch.setenv("DATABASE_URL", "dbname=botkeytest")
    assert nbk.main(["zz-seal-bot", "--seal"]) == 0
    out = capsys.readouterr()
    text = out.out + out.err
    assert raw not in text
    assert "status: sealed" in text
    assert seen["params"] == ("zz-seal-bot", raw)
    assert nbk.main(["zz-seal-bot", "--seal", "--sql-only"]) == 1
    again = capsys.readouterr()
    assert raw not in again.out + again.err


def test_sql_only_hint_has_no_key(tmp_path, capsys, monkeypatch):
    monkeypatch.setattr(nbk, "KEY_DIR", str(tmp_path))
    monkeypatch.delenv("DATABASE_URL", raising=False)
    assert nbk.main(["zz-hint-bot", "--sql-only"]) == 0
    out = capsys.readouterr().out
    raw = (tmp_path / "zz-hint-bot.key").read_text().strip()
    assert raw not in out
    assert "--seal" in out


def test_missing_file_is_not_created(tmp_path, capsys, monkeypatch):
    monkeypatch.setattr(nbk, "KEY_DIR", str(tmp_path))
    monkeypatch.setenv("DATABASE_URL", "dbname=botkeytest")
    with pytest.raises(SystemExit):
        nbk.main(["zz-absent-bot", "--seal"])
    assert not (tmp_path / "zz-absent-bot.key").exists()
    assert "rgk_" not in capsys.readouterr().out


def test_unauthorized_unknown_unsealed_and_portal_night(cur):
    night = "rgk_" + "n" * 40
    other = "rgk_" + "o" * 40
    add_key(cur, "portal-night-bot", night, rate=30)
    add_key(cur, "zz-unsealed", other)
    before_night = identity(cur, "portal-night-bot")
    before_other = identity(cur, "zz-unsealed")
    unknown, _ = apply(cur, "zz-no-such-bot", "p" * 32)
    unsealed, _ = apply(cur, "zz-unsealed", "p" * 32)
    night_apply, _ = apply(cur, "portal-night-bot", "p" * 32)
    night_seal = seal(cur, "portal-night-bot", night)
    night_ok = call(cur, "select public.approve_bot_key_pickup(%s)", ("portal-night-bot",))
    assert unknown == {"ok": False, "error": "unauthorized"}
    assert unsealed == {"ok": False, "error": "unauthorized"}
    assert night_apply == {"ok": False, "error": "unauthorized"}
    assert night_seal == {"ok": False, "error": "unauthorized"}
    assert night_ok == {"ok": False, "error": "unauthorized"}
    assert identity(cur, "portal-night-bot") == before_night
    assert identity(cur, "zz-unsealed") == before_other
    assert cur.execute("select count(*) from bots.bot_key_pickup").fetchone()[0] == 0
    blob = dumped([unknown, unsealed, night_apply, night_seal, night_ok])
    assert night not in blob and other not in blob and ("p" * 32) not in blob


def test_wrong_proof_does_not_replace_or_deliver(cur):
    raw = "rgk_" + "a" * 40
    proof = "proof-" + secrets.token_urlsafe(24)
    other = "proof-" + secrets.token_urlsafe(24)
    add_key(cur, "zz-lock", raw)
    assert seal(cur, "zz-lock", "rgk_" + "b" * 40) == {"ok": False, "error": "refused"}
    assert seal(cur, "zz-lock", raw)["ok"] is True
    pending, digest = apply(cur, "zz-lock", proof)
    locked, _ = apply(cur, "zz-lock", other)
    assert pending["ok"] is True and pending["status"] == "pending"
    assert pending["proof_prefix"] == digest[:8]
    assert "key" not in pending
    assert locked == {"ok": False, "error": "pending_locked"}
    assert call(cur, "select public.approve_bot_key_pickup(%s)", ("zz-nope",))["ok"] is False
    approved = call(cur, "select public.approve_bot_key_pickup(%s)", ("zz-lock",))
    assert approved == {"ok": True, "bot_id": "zz-lock", "status": "approved"}
    assert "key" not in approved
    denied, _ = apply(cur, "zz-lock", other)
    assert denied == {"ok": False, "error": "unauthorized"}
    stored = cur.execute(
        """select p.status, encode(extensions.digest(p.pickup_key, 'sha256'), 'hex')
             from bots.bot_key_pickup p
             join bots.ingest_keys k on k.id = p.key_id
            where k.bot_id = 'zz-lock'"""
    ).fetchone()
    assert stored == ("approved", hashlib.sha256(raw.encode()).hexdigest())
    blob = dumped([pending, locked, approved, denied])
    assert raw not in blob and proof not in blob and other not in blob


def test_legitimate_pickup_then_replay(cur):
    raw = "rgk_" + "c" * 40
    other_raw = "rgk_" + "d" * 40
    proof = "proof-" + secrets.token_urlsafe(24)
    add_key(cur, "zz-ok", raw, rate=41)
    add_key(cur, "zz-other", other_raw)
    before = identity(cur, "zz-ok")
    other_before = identity(cur, "zz-other")
    notices = []
    cur.add_notice_handler(lambda diag: notices.append(diag.message_primary or ""))
    assert seal(cur, "zz-ok", raw) == {"ok": True, "bot_id": "zz-ok", "status": "sealed"}
    again = seal(cur, "zz-ok", raw)
    assert again["ok"] is True and "key" not in again
    pending, digest = apply(cur, "zz-ok", proof)
    assert pending["status"] == "pending" and pending["proof_prefix"] == digest[:8]
    listed = cur.execute("select bot_id, status, proof_prefix from public.pending_bot_key_pickups()").fetchall()
    assert ("zz-ok", "pending", digest[:8]) in listed
    assert call(cur, "select public.approve_bot_key_pickup(%s)", ("zz-ok",))["status"] == "approved"
    assert call(cur, "select public.approve_bot_key_pickup(%s)", ("zz-ok",))["status"] == "approved"
    delivered, _ = apply(cur, "zz-ok", proof)
    assert delivered["status"] == "delivered"
    assert hashlib.sha256(delivered["key"].encode()).hexdigest() == before[2]
    assert other_raw not in dumped(delivered) and proof not in dumped(delivered)
    replay, _ = apply(cur, "zz-ok", proof)
    assert replay == {"ok": False, "error": "already_delivered"}
    assert "key" not in replay
    wiped = cur.execute(
        """select p.pickup_key, p.proof_hash, p.status
             from bots.bot_key_pickup p
             join bots.ingest_keys k on k.id = p.key_id
            where k.bot_id = 'zz-ok'"""
    ).fetchone()
    assert wiped == (None, None, "delivered")
    assert identity(cur, "zz-ok") == before
    assert identity(cur, "zz-other") == other_before
    reseal = seal(cur, "zz-ok", raw)
    assert reseal == {"ok": True, "bot_id": "zz-ok", "status": "sealed"} and "key" not in reseal
    still, _ = apply(cur, "zz-ok", proof)
    assert still["status"] == "pending" and "key" not in still
    blob = dumped([pending, listed, replay, reseal, still, notices])
    assert raw not in blob and other_raw not in blob and proof not in blob
    assert delivered["key"] not in blob


def test_clear_lets_the_right_proof_apply(cur):
    raw = "rgk_" + "e" * 40
    first = "f" * 40
    second = "s" * 40
    add_key(cur, "zz-clear", raw)
    seal(cur, "zz-clear", raw)
    apply(cur, "zz-clear", first)
    cleared = call(cur, "select public.clear_bot_key_pickup(%s)", ("zz-clear",))
    assert cleared == {"ok": True, "bot_id": "zz-clear", "status": "cleared"}
    assert "key" not in cleared
    kept = cur.execute(
        """select p.status, encode(extensions.digest(p.pickup_key, 'sha256'), 'hex')
             from bots.bot_key_pickup p
             join bots.ingest_keys k on k.id = p.key_id
            where k.bot_id = 'zz-clear'"""
    ).fetchone()
    assert kept == (None, hashlib.sha256(raw.encode()).hexdigest())
    pending, digest = apply(cur, "zz-clear", second)
    assert pending["proof_prefix"] == digest[:8]
    old, _ = apply(cur, "zz-clear", first)
    assert old == {"ok": False, "error": "pending_locked"}
    blob = dumped([cleared, pending, old])
    assert raw not in blob and first not in blob and second not in blob


def test_site_roles_cannot_read_or_call(cur):
    import psycopg
    raw = "rgk_" + "f" * 40
    add_key(cur, "zz-priv", raw)
    seal(cur, "zz-priv", raw)
    for role in ("anon", "authenticated", "bot_writer"):
        assert cur.execute(
            "select has_function_privilege(%s, 'public.bot_key_apply(text,text)', 'execute')",
            (role,),
        ).fetchone()[0] is False
    assert cur.execute(
        "select has_function_privilege('service_role', 'public.bot_key_apply(text,text)', 'execute')"
    ).fetchone()[0] is True
    for role in ("anon", "authenticated", "bot_writer", "service_role"):
        for priv in ("select", "insert", "update", "delete"):
            assert cur.execute(
                "select has_table_privilege(%s, 'bots.bot_key_pickup', %s)",
                (role, priv),
            ).fetchone()[0] is False
    cur.execute("set local role bot_writer")
    got = cur.execute("select bot_id, active, rate_limit_per_min from bots.ingest_keys where bot_id = 'zz-priv'").fetchone()
    assert got == ("zz-priv", True, 30)
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        cur.execute("select pickup_key from bots.bot_key_pickup")
