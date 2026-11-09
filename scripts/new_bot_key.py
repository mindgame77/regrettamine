#!/usr/bin/env python3
"""Make an ingest key for one bot, after Alex OKs that bot (Alex, 2026-10-28).

    python3 scripts/new_bot_key.py <bot_id>            # with DATABASE_URL set: writes the file and registers it
    python3 scripts/new_bot_key.py <bot_id> --sql-only # no DATABASE_URL: writes the file, prints the SQL to run
    python3 scripts/new_bot_key.py <bot_id> --seal     # seal the existing file for pickup; does not print the key

The raw key is written only to /home/box/regretamin-keys/<bot_id>.key (directory 700, file 600) and is never
printed. The database stores only its sha256 (public.register_bot_key). Refuses to overwrite an existing key file.
If registering fails, the new key file is removed.
--seal reads that file and calls public.seal_bot_key_pickup. It does not make a second key and does not print the key.
"""
import argparse
import hashlib
import os
import re
import secrets
import sys

KEY_DIR = os.environ.get("REGRETAMIN_KEY_DIR", "/home/box/regretamin-keys")
BOT_RE = re.compile(r"^[a-z0-9][a-z0-9-]{2,62}$")
PUBLIC_FIELDS = ("ok", "bot_id", "status", "error", "name")


def write_key(bot_id: str, key_dir: str | None = None) -> tuple[str, str]:
    """Create the key file; return (path, sha256 hex). Never returns the raw key."""
    key_dir = key_dir or KEY_DIR
    if not BOT_RE.match(bot_id):
        raise SystemExit("bot_id must be 3-63 characters: lowercase letters, digits, hyphens")
    os.makedirs(key_dir, mode=0o700, exist_ok=True)
    os.chmod(key_dir, 0o700)
    path = os.path.join(key_dir, f"{bot_id}.key")
    key = "rgk_" + secrets.token_urlsafe(32)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)  # fails if the file exists
    with os.fdopen(fd, "w") as f:
        f.write(key + "\n")
    os.chmod(path, 0o600)
    return path, hashlib.sha256(key.encode()).hexdigest()


def key_path(bot_id: str, key_dir: str | None = None) -> str:
    if not BOT_RE.match(bot_id):
        raise SystemExit("bot_id must be 3-63 characters: lowercase letters, digits, hyphens")
    return os.path.join(key_dir or KEY_DIR, f"{bot_id}.key")


def load_key(bot_id: str, key_dir: str | None = None) -> str:
    """Read the key file. Callers must not print the result."""
    path = key_path(bot_id, key_dir)
    if not os.path.exists(path):
        raise SystemExit("no key file")
    with open(path) as fh:
        raw = fh.read()
    if raw.endswith("\n"):
        raw = raw[:-1]
    if not raw or "\n" in raw or raw.strip() != raw:
        raise SystemExit("key file must be one line")
    return raw


def connect_db(url: str):
    import psycopg
    return psycopg.connect(url)


def as_obj(value):
    if isinstance(value, str):
        import json
        return json.loads(value)
    return value


def seal_on(conn, bot_id: str, raw: str) -> dict:
    reg = conn.execute("select to_regprocedure('public.seal_bot_key_pickup(text,text)')").fetchone()[0]
    if reg is None:
        return {"ok": True, "status": "seal is not installed"}
    return as_obj(conn.execute("select public.seal_bot_key_pickup(%s, %s)", (bot_id, raw)).fetchone()[0])


def redact(text: str, secret: str) -> str:
    if secret and len(secret) >= 20 and secret in text:
        return text.replace(secret, "[redacted]")
    return text


def format_public(result: dict) -> str:
    if not isinstance(result, dict):
        return "not sealed"
    lines = []
    for field in PUBLIC_FIELDS:
        if result.get(field) is not None:
            lines.append(f"{field}: {result[field]}")
    return "\n".join(lines)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("bot_id")
    ap.add_argument("--sql-only", action="store_true")
    ap.add_argument("--seal", action="store_true")
    a = ap.parse_args(argv)
    url = os.environ.get("DATABASE_URL", "").strip()
    if a.seal:
        if a.sql_only or not url:
            print("seal needs DATABASE_URL and does not print the key", file=sys.stderr)
            return 1
        raw = load_key(a.bot_id)
        try:
            with connect_db(url) as conn:
                result = seal_on(conn, a.bot_id, raw)
        except Exception as exc:
            print(redact(f"not sealed: {exc}", raw), file=sys.stderr)
            return 1
        print(redact(format_public(result), raw))
        return 0 if result.get("ok") else 1
    path, hashed = write_key(a.bot_id)
    if a.sql_only or not url:
        print(f"key file: {path}")
        print(f"run as service role: select public.register_bot_key('{a.bot_id}', '{hashed}');")
        print(f"if that returns ok=false, delete {path}")
        print(f"pickup later: python3 scripts/new_bot_key.py {a.bot_id} --seal")
        return 0
    raw = load_key(a.bot_id)
    registered = False
    try:
        with connect_db(url) as conn:
            result = as_obj(conn.execute("select public.register_bot_key(%s, %s)", (a.bot_id, hashed)).fetchone()[0])
            if not result.get("ok"):
                os.remove(path)
                print(f"not created: {result.get('error')}", file=sys.stderr)
                return 1
            registered = True
            print(f"key file: {path}\nbot_id: {result['bot_id']}\nkey name: {result['name']}")
            sealed = seal_on(conn, a.bot_id, raw)
    except Exception as exc:
        if not registered and os.path.exists(path):
            os.remove(path)
            raise
        print(redact(f"not sealed: {exc}", raw), file=sys.stderr)
        return 1
    print(redact(format_public(sealed), raw))
    if sealed.get("ok"):
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
