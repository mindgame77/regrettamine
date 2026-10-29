#!/usr/bin/env python3
"""Make an ingest key for one bot, after Alex OKs that bot (Alex, 2026-10-28).

    python3 scripts/new_bot_key.py <bot_id>            # with DATABASE_URL set: writes the file and registers it
    python3 scripts/new_bot_key.py <bot_id> --sql-only # no DATABASE_URL: writes the file, prints the SQL to run

The raw key is written only to /home/box/regretamin-keys/<bot_id>.key (directory 700, file 600) and is never
printed. The database stores only its sha256 (public.register_bot_key). Refuses to overwrite an existing key file.
If registering fails, the new key file is removed.
"""
import argparse
import hashlib
import os
import re
import secrets
import sys

KEY_DIR = os.environ.get("REGRETAMIN_KEY_DIR", "/home/box/regretamin-keys")
BOT_RE = re.compile(r"^[a-z0-9][a-z0-9-]{2,62}$")


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


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("bot_id")
    ap.add_argument("--sql-only", action="store_true")
    a = ap.parse_args(argv)
    path, h = write_key(a.bot_id)
    url = os.environ.get("DATABASE_URL", "").strip()
    if a.sql_only or not url:
        print(f"key file: {path}")
        print(f"run as service role: select public.register_bot_key('{a.bot_id}', '{h}');")
        print(f"if that returns ok=false, delete {path}")
        return 0
    import psycopg
    try:
        with psycopg.connect(url) as c:
            r = c.execute("select public.register_bot_key(%s, %s)", (a.bot_id, h)).fetchone()[0]
    except Exception:
        os.remove(path)
        raise
    if not r.get("ok"):
        os.remove(path)
        print(f"not created: {r.get('error')}", file=sys.stderr)
        return 1
    print(f"key file: {path}\nbot_id: {r['bot_id']}\nkey name: {r['name']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
