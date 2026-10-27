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


@pytest.fixture(scope="session", autouse=True)
def _legacy_auto_promote():
    """Keeps the old auto-promote switch on in the test database. toxy-enricher publishes at ingest either way.
    Researcher uploads do not. Tests that still exercise a batch disable the enricher insert trigger in that transaction."""
    if not DATABASE_URL:
        yield
        return
    import psycopg
    from psycopg import sql
    with psycopg.connect(DATABASE_URL) as c:
        # Bot tables live in bots. Tests (and this insert) use unqualified names.
        # The role setting is test-database only; the migration does not change production roles.
        c.execute("set search_path to bots, public")
        dbname = c.execute("select current_database()").fetchone()[0]
        user = c.execute("select current_user").fetchone()[0]
        c.execute(sql.SQL("alter role {} in database {} set search_path = bots, public").format(
            sql.Identifier(user), sql.Identifier(dbname)))
        c.execute("insert into ingest_settings(key, value) values ('auto_promote_enrichment', '1') "
                  "on conflict (key) do update set value = '1'")
        c.execute(sql.SQL("alter database {} set app.test_auto_publish = '1'").format(sql.Identifier(dbname)))
    yield
