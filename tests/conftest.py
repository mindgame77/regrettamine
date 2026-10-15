"""Shared helpers. Site data always comes from the database (seeded from the snapshot)."""
import os

import pytest

DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()


def db_site():
    """Seed the test database and return (home, funds) through the build's own DB path."""
    if not DATABASE_URL:
        pytest.skip("DATABASE_URL is not set")
    from scripts.seed import main as seed_main
    from build import load_db

    seed_main()
    return load_db()
