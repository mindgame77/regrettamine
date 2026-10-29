"""Founded year in the firm header (Alex 2026-10-29): firm_page().firm.founded_year from firms.founded_year."""
import os
import pathlib

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIG = ROOT / "supabase/migrations/20261029130000_firm_founded_year.sql"
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()


def test_migration_text():
    s = MIG.read_text()
    assert s.count("'founded_year', f.founded_year") == 2
    assert s.count("'social', public._firm_social(f.id)") == 2
    assert "delete from public.firm_page_cache" in s
    assert (ROOT / "supabase/rollbacks/20261029130000_firm_founded_year.sql").exists()


@pytest.mark.skipif(not DATABASE_URL, reason="needs DATABASE_URL")
def test_firm_page_carries_founded_year():
    import psycopg
    with psycopg.connect(DATABASE_URL) as c:
        slug, fid = c.execute("select slug, id from firms order by slug limit 1").fetchone()
        q = "select public.firm_page(%s, gen_random_uuid(), false, null)->'firm'->'founded_year'"
        c.execute("update firms set founded_year = 1972 where id = %s", (fid,))
        assert c.execute(q, (slug,)).fetchone()[0] == 1972
        c.execute("update firms set founded_year = null where id = %s", (fid,))
        assert c.execute(q, (slug,)).fetchone()[0] is None
        c.rollback()
