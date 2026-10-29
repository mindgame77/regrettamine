"""Step C (Alex, 2026-10-28): a Checker publish recounts that firm's saved checks in firm_check_results.
The 10 checks stay off: with no 'checks_on' setting nothing is recounted."""
import os
import pathlib
import uuid

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIG = ROOT / "supabase" / "migrations" / "20261029080000_recount_on_publish.sql"
DATABASE_URL = os.environ.get("DATABASE_URL")


def test_migration_renames_and_keeps_checks_off():
    s = MIG.read_text()
    assert "alter table public.firm_check_pills rename to firm_check_results" in s
    assert "raise exception 'firm_check_pills is not empty" in s
    assert "key = 'checks_on'" in s
    assert "insert into bots.ingest_settings" not in s  # never turns the checks on


def test_rulebook_names_the_new_table():
    g = (ROOT / "docs" / "PAGE_DATA_GUIDE.md").read_text(encoding="utf-8")
    a81 = g[g.index("- **A8.1**"):g.index("- **A8.2**")]
    assert "saved, in `firm_check_results`" in a81


@pytest.mark.skipif(not DATABASE_URL, reason="needs DATABASE_URL")
def test_checker_publish_recounts_only_when_checks_on():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        assert cur.execute("select to_regclass('public.firm_check_results') is not null, to_regclass('public.firm_check_pills') is null").fetchone() == (True, True)
        reg = "zz-rc-" + uuid.uuid4().hex[:8]
        cur.execute("insert into research_queue (registry_id, name, priority, status) values (%s, 'Recount Lab', 5, 'submitted')", (reg,))
        fid = cur.execute(
            "insert into firms(slug, name, published, data_status, registry_id) values (%s, 'Recount Lab', true, 'real', %s) returning id",
            ("rc-" + uuid.uuid4().hex[:8], reg),
        ).fetchone()[0]
        ins = "insert into publish_checks(origin, bot_id, firm_id, outcome) values ('submission', 'checker', %s, 'published')"
        cur.execute("delete from bots.ingest_settings where key = 'checks_on'")
        cur.execute(ins, (fid,))
        assert cur.execute("select count(*) from firm_check_results where firm_id = %s", (fid,)).fetchone()[0] == 0
        cur.execute("insert into bots.ingest_settings(key, value) values ('checks_on', 'true')")
        cur.execute("insert into publish_checks(origin, bot_id, firm_id, outcome) values ('submission', 'checker', %s, 'note')", (fid,))
        assert cur.execute("select count(*) from firm_check_results where firm_id = %s", (fid,)).fetchone()[0] == 0
        cur.execute(ins, (fid,))
        assert cur.execute("select count(*) from firm_check_results where firm_id = %s and checks is not null", (fid,)).fetchone()[0] == 1
        conn.rollback()
