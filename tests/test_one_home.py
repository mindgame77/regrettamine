"""One home per kind, lab firms only. Exact copies can be removed. The page rows stay."""
import os
import uuid

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")


def _rows(cur):
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, row)) for row in cur.fetchall()]


def _lab(cur):
    slug = "home-" + uuid.uuid4().hex[:8]
    reg = "zz-home-" + uuid.uuid4().hex[:8]
    cur.execute("insert into research_queue (registry_id, name, priority, status) values (%s, 'Home Lab', 5, 'submitted')", (reg,))
    fid = cur.execute(
        "insert into firms(slug, name, legal_name, published, data_status, registry_id) "
        "values (%s, 'Home Lab', 'Home Lab Legal LLC', true, 'real', %s) returning id",
        (slug, reg),
    ).fetchone()[0]
    cur.execute(
        "insert into ingest_settings(key, value) values ('lab_firm_slugs', %s) "
        "on conflict (key) do update set value = case when ingest_settings.value like %s then ingest_settings.value "
        "else coalesce(ingest_settings.value, '') || ',' || excluded.value end",
        (slug, "%" + slug + "%"),
    )
    return fid, slug


def test_rules_are_written_and_the_page_is_untouched():
    from pathlib import Path
    guide = Path("docs/PAGE_DATA_GUIDE.md").read_text(encoding="utf-8")
    sql = Path("supabase/migrations/20261028140000_one_home_lab.sql").read_text(encoding="utf-8")
    rollback = Path("supabase/rollbacks/20261028140000_one_home_lab.sql").read_text(encoding="utf-8")
    js = Path("launch/js/company.js").read_text(encoding="utf-8")
    assert "home_merge_backup" in guide and "not deleted without Alex" in guide
    assert "stays the public fact counter" in guide
    assert "lab_one_home(true)" in sql
    assert "drop table public.home_merge_backup" not in rollback
    assert "checked_on" not in js


def test_exact_copy_is_removed_and_a_different_value_stays():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        fid, slug = _lab(cur)
        url = "https://techcrunch.com/2026/10/28/home-" + uuid.uuid4().hex[:6]
        ids = []
        for headline in ("Home Lab raises", "Home Lab raises", "Home Lab raises a different fund"):
            pid = cur.execute(
                "insert into press_items(publisher, domain, url, headline, data_status, retrieved_at) "
                "values ('TechCrunch', 'techcrunch.com', %s, %s, 'real', now()) returning id",
                (url, headline),
            ).fetchone()[0]
            cur.execute(
                "insert into press_item_firms(press_item_id, firm_id, sort_order, check_mark) "
                "values (%s, %s, 1, 'checked_correct')",
                (pid, fid),
            )
            ids.append(pid)
        dry = _rows(cur.execute("select * from lab_one_home(false) where slug = %s and kind = 'news'", (slug,)))
        assert dry and dry[0]["duplicates"] == 1 and dry[0]["disagreements"] == 1
        assert cur.execute(
            "select count(*) from press_item_firms where firm_id = %s", (fid,)
        ).fetchone()[0] == 3
        wrote = _rows(cur.execute("select * from lab_one_home(true) where slug = %s and kind = 'news'", (slug,)))
        assert wrote[0]["duplicates"] == 1 and wrote[0]["disagreements"] == 1
        left = cur.execute(
            "select p.headline from press_items p join press_item_firms pf on pf.press_item_id = p.id "
            "where pf.firm_id = %s order by p.headline",
            (fid,),
        ).fetchall()
        assert len(left) == 2
        assert cur.execute(
            "select count(*) from home_merge_backup where firm_id = %s", (fid,)
        ).fetchone()[0] >= 1
        assert cur.execute(
            "select count(*) from publish_checks where firm_id = %s and reason like 'home merge:%%'",
            (fid,),
        ).fetchone()[0] >= 1
        again = _rows(cur.execute("select * from lab_one_home(false) where slug = %s and kind = 'news'", (slug,)))
        assert again[0]["duplicates"] == 0 and again[0]["disagreements"] == 1
        alias = cur.execute(
            "select alias_type, source from firm_aliases where firm_id = %s and lower(alias) = lower('Home Lab Legal LLC')",
            (fid,),
        ).fetchone()
        assert alias == ("legal", "sec_legal")

        off = "off-" + uuid.uuid4().hex[:8]
        oreg = "zz-offhome-" + uuid.uuid4().hex[:8]
        same = "https://techcrunch.com/2026/01/02/same-off-" + uuid.uuid4().hex[:4]
        cur.execute("insert into research_queue (registry_id, name, priority, status) values (%s, 'Off', 5, 'submitted')", (oreg,))
        oid = cur.execute(
            "insert into firms(slug, name, published, data_status, registry_id) values (%s, 'Off', true, 'real', %s) returning id",
            (off, oreg),
        ).fetchone()[0]
        pids = []
        for _ in range(2):
            pids.append(cur.execute(
                "insert into press_items(url, headline, data_status, retrieved_at) values (%s, 'Same', 'real', now()) returning id",
                (same,),
            ).fetchone()[0])
        cur.execute(
            "insert into press_item_firms(press_item_id, firm_id, check_mark) values (%s, %s, 'checked_correct'), (%s, %s, 'checked_correct')",
            (pids[0], oid, pids[1], oid),
        )
        cur.execute("select lab_one_home(true)")
        assert cur.execute("select count(*) from press_item_firms where firm_id = %s", (oid,)).fetchone()[0] == 2
        conn.rollback()
