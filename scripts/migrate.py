#!/usr/bin/env python3
"""Apply supabase/migrations/*.sql in order.

    DATABASE_URL=postgresql:///regrettamine python3 scripts/migrate.py
"""
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    url = os.environ.get("DATABASE_URL", "").strip()
    if not url:
        sys.exit("DATABASE_URL is required")
    import psycopg

    files = sorted((ROOT / "supabase" / "migrations").glob("*.sql"))
    if not files:
        sys.exit("no migrations found")
    with psycopg.connect(url) as conn:
        for path in files:
            conn.execute(path.read_text(encoding="utf-8"))
            print(f"applied {path.name}")
        conn.commit()


if __name__ == "__main__":
    main()
