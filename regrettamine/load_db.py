"""Full site data from the database, for tests and tools.

Same full-bundle sources as the old site build: service role, DATABASE_URL, or
SITE_BUNDLE. The anon public bundle is not enough. Shared copy tokens are left
as stored.
"""
import json
import os
from pathlib import Path


def load_db():
    """Return (home, funds) from the full bundle."""
    from regrettamine.assemble import assemble_site
    from regrettamine.supabase_load import fetch_bundle, fetch_db_bundle

    url = os.environ.get("SUPABASE_URL", "").strip()
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    db = os.environ.get("DATABASE_URL", "").strip()
    saved = os.environ.get("SITE_BUNDLE", "").strip()
    if url and key:
        print("source: supabase (service role, server-side)")
        bundle = fetch_bundle(url, key)
    elif db:
        print("source: database (DATABASE_URL)")
        bundle = fetch_db_bundle(db)
    elif saved:
        print(f"source: saved database bundle {saved}")
        bundle = json.loads(Path(saved).read_text(encoding="utf-8"))
    else:
        raise SystemExit("load_db needs the full bundle (service key, DATABASE_URL or SITE_BUNDLE)")
    return assemble_site(bundle)
