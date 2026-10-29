"""One ingest key per bot (Alex, 2026-10-28): public.register_bot_key + scripts/new_bot_key.py.
Database tests run in a rolled-back transaction."""
import hashlib
import importlib.util
import os
import pathlib
import stat
import uuid

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIG = (ROOT / "supabase/migrations/20261029100000_register_bot_key.sql").read_text()
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
spec = importlib.util.spec_from_file_location("new_bot_key", ROOT / "scripts/new_bot_key.py")
nbk = importlib.util.module_from_spec(spec)
spec.loader.exec_module(nbk)


def test_migration_additive_and_server_only():
    low = MIG.lower()
    for bad in ("alter table", "drop ", "update ", "delete ", "create policy", "grant execute on function public.register_bot_key(text, text) to anon"):
        assert bad not in low, bad
    assert "revoke all on function public.register_bot_key(text, text) from public, anon, authenticated;" in MIG
    assert "grant execute on function public.register_bot_key(text, text) to service_role;" in MIG
    assert "security definer set search_path = bots, public" in low


def test_key_file_private_and_hash_matches(tmp_path, capsys):
    d = tmp_path / "keys"
    path, h = nbk.write_key("zz-test-bot", str(d))
    raw = pathlib.Path(path).read_text().strip()
    assert stat.S_IMODE(os.stat(path).st_mode) == 0o600 and stat.S_IMODE(os.stat(d).st_mode) == 0o700
    assert hashlib.sha256(raw.encode()).hexdigest() == h and len(raw) >= 40
    assert raw not in capsys.readouterr().out
    with pytest.raises(FileExistsError):
        nbk.write_key("zz-test-bot", str(d))
    with pytest.raises(SystemExit):
        nbk.write_key("Bad Bot!", str(d))


def test_sql_only_never_prints_key(tmp_path, capsys, monkeypatch):
    monkeypatch.setattr(nbk, "KEY_DIR", str(tmp_path))
    assert nbk.main(["zz-sql-bot", "--sql-only"]) == 0
    out = capsys.readouterr().out
    raw = (tmp_path / "zz-sql-bot.key").read_text().strip()
    assert raw not in out and "register_bot_key('zz-sql-bot'" in out



@pytest.fixture()
def cur():
    if not DATABASE_URL:
        pytest.skip("DATABASE_URL is not set")
    import psycopg
    with psycopg.connect(DATABASE_URL) as c:
        if c.execute("select to_regprocedure('public.register_bot_key(text,text)')").fetchone()[0] is None:
            pytest.skip("register_bot_key migration not applied")
        try:
            yield c
        finally:
            c.rollback()


def reg(c, bot, h=None):
    return c.execute("select public.register_bot_key(%s, %s)", (bot, h or hashlib.sha256(uuid.uuid4().bytes).hexdigest())).fetchone()[0]


def test_register_links_key_to_bot(cur):
    r = reg(cur, "zz-reg-a")
    assert r["ok"] and r["bot_id"] == "zz-reg-a"
    row = cur.execute("select bot_id, active, rate_limit_per_min from bots.ingest_keys where id = %s", (r["key_id"],)).fetchone()
    assert row == ("zz-reg-a", True, 30)


def test_refuses_second_key_duplicate_hash_and_bad_input(cur):
    h = hashlib.sha256(b"x" + uuid.uuid4().bytes).hexdigest()
    assert reg(cur, "zz-reg-b", h)["ok"]
    assert reg(cur, "zz-reg-b")["ok"] is False
    assert reg(cur, "zz-reg-c", h)["ok"] is False
    assert reg(cur, "Bad Bot")["ok"] is False
    assert reg(cur, "zz-reg-d", "nothex")["ok"] is False


def test_existing_keys_untouched(cur):
    before = cur.execute("select id, name, key_hash, active, bot_id from bots.ingest_keys order by id").fetchall()
    reg(cur, "zz-reg-e")
    after = cur.execute("select id, name, key_hash, active, bot_id from bots.ingest_keys where name not like 'bot-zz-reg-e-%%' order by id").fetchall()
    assert before == after


@pytest.mark.parametrize("role", ["anon", "authenticated"])
def test_site_roles_cannot_call(cur, role):
    assert cur.execute("select has_function_privilege(%s, 'public.register_bot_key(text,text)', 'execute')", (role,)).fetchone()[0] is False
