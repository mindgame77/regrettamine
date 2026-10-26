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
    """Older tests expect research to publish on insert. Production never does: the switch only works in a database
    that also has app.test_auto_publish = '1' (set here, test database only). Publishing on prod goes through a
    publish batch (create -> dry run -> Alex approves -> run). Tests that check the holding-area behaviour switch
    it off inside their own rolled-back transaction."""
    if not DATABASE_URL:
        yield
        return
    import psycopg
    with psycopg.connect(DATABASE_URL) as c:
        c.execute("insert into ingest_settings(key, value) values ('auto_promote_enrichment', '1') "
                  "on conflict (key) do update set value = '1'")
        from psycopg import sql
        dbname = c.execute("select current_database()").fetchone()[0]
        c.execute(sql.SQL("alter database {} set app.test_auto_publish = '1'").format(sql.Identifier(dbname)))
    yield
