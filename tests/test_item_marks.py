"""Lab item marks: one hourly limit's neighbor, three columns, old fields kept."""
import json
import os
import uuid

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")


def _j(v):
    return v if isinstance(v, dict) else json.loads(v)


def test_marks_live_on_the_item_and_the_page_is_unchanged():
    from pathlib import Path
    guide = Path("docs/PAGE_DATA_GUIDE.md").read_text(encoding="utf-8")
    sql = Path("supabase/migrations/20261028130000_hour_cap_and_marks.sql").read_text(encoding="utf-8")
    js = Path("launch/js/company.js").read_text(encoding="utf-8")
    mock = Path("docs/design/mockups/sequoia-checked-date.html").read_text(encoding="utf-8")
    assert "not on `fact_sources`" in guide
    assert "marks_fold_backup" in guide
    assert "awaiting Alex" in Path("docs/design/README.md").read_text(encoding="utf-8")
    assert "add column if not exists checked_on" in sql
    assert "drop column" not in sql
    assert "checked_on" not in js
    assert "checked Oct 27, 2026" in mock
    assert "class=\"ckd new\"" in mock


def test_fold_copies_lab_dates_and_leaves_the_old_fields():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        when = "2026-10-27 21:45:00+00"
        slug = "marks-" + uuid.uuid4().hex[:8]
        reg = "zz-marks-" + uuid.uuid4().hex[:8]
        cur.execute("insert into research_queue (registry_id, name, priority, status) values (%s, 'Mark Lab', 5, 'submitted')", (reg,))
        fid = cur.execute(
            "insert into firms(slug, name, published, data_status, registry_id) values (%s, 'Mark Lab', true, 'real', %s) returning id",
            (slug, reg),
        ).fetchone()[0]
        cur.execute(
            "insert into ingest_settings(key, value) values ('lab_firm_slugs', %s) "
            "on conflict (key) do update set value = case when ingest_settings.value like %s then ingest_settings.value "
            "else coalesce(ingest_settings.value, '') || ',' || excluded.value end",
            (slug, "%" + slug + "%"),
        )
        cur.execute(
            "insert into firm_check_rows(firm_id, n, title, descr, state, searched_at) "
            "values (%s, 1, 'Sanctions', 'Lists', 'clear', %s)",
            (fid, when),
        )
        tid = cur.execute(
            "insert into timeline_events(firm_id, date_label, kind, body, sort_order, source_url, check_mark, last_checked_at) "
            "values (%s, '2026-01-07', 'Reported', 'Mark Lab example', 1, "
            "'https://techcrunch.com/2026/01/07/mark-lab', 'checked_correct', %s) returning id",
            (fid, when),
        ).fetchone()[0]
        cur.execute(
            "insert into timeline_events(firm_id, date_label, kind, body, sort_order, check_mark) "
            "values (%s, '2026-01-08', 'Reported', 'Mark Lab not checked', 2, 'not_checked')",
            (fid,),
        )
        off = "off-" + uuid.uuid4().hex[:8]
        oreg = "zz-offmarks-" + uuid.uuid4().hex[:8]
        cur.execute("insert into research_queue (registry_id, name, priority, status) values (%s, 'Off Lab', 5, 'submitted')", (oreg,))
        oid = cur.execute(
            "insert into firms(slug, name, published, data_status, registry_id) values (%s, 'Off Lab', true, 'real', %s) returning id",
            (off, oreg),
        ).fetchone()[0]
        cur.execute(
            "insert into firm_check_rows(firm_id, n, title, descr, state, searched_at) "
            "values (%s, 1, 'Sanctions', 'Lists', 'clear', %s)",
            (oid, when),
        )
        got = _j(cur.execute("select fold_legacy_marks()").fetchone()[0])
        assert got["checks"] >= 1 and got["timeline"] >= 1
        row = cur.execute(
            "select checked_on, checked_by, source_level, searched_at from firm_check_rows where firm_id = %s and n = 1",
            (fid,),
        ).fetchone()
        assert row[0] is not None and row[1] is None and row[2] is None
        assert row[3] is not None and row[0] == row[3]
        news = cur.execute(
            "select checked_on, checked_by, source_level, check_mark, last_checked_at from timeline_events where id = %s",
            (tid,),
        ).fetchone()
        assert news[0] == news[4] and news[1] is None and news[2] == 2 and news[3] == "checked_correct"
        quiet = cur.execute(
            "select checked_on, source_level from timeline_events where firm_id = %s and check_mark = 'not_checked'",
            (fid,),
        ).fetchone()
        assert quiet == (None, None)
        other = cur.execute(
            "select checked_on from firm_check_rows where firm_id = %s",
            (oid,),
        ).fetchone()[0]
        assert other is None
        assert cur.execute(
            "select count(*) from marks_fold_backup where firm_id = %s and table_name = 'timeline_events'",
            (fid,),
        ).fetchone()[0] == 1
        assert cur.execute(
            "select count(*) from marks_fold_backup where firm_id = %s and table_name = 'firm_check_rows'",
            (fid,),
        ).fetchone()[0] == 1
        again = _j(cur.execute("select fold_legacy_marks()").fetchone()[0])
        assert again["checks"] == 0 and again["press"] == 0 and again["timeline"] == 0
        assert cur.execute(
            "select count(*) from marks_fold_backup where firm_id = %s",
            (fid,),
        ).fetchone()[0] == 2

        item = {
            "outlet": "TechCrunch", "headline": "Mark Lab raises a fund",
            "url": "https://techcrunch.com/2026/10/28/mark-lab-" + uuid.uuid4().hex[:6],
            "date": "2026-10-28", "snippet": "Mark Lab raised",
        }
        cur.execute(
            "insert into research_submissions(registry_id, bot_id, payload, record_count, valid) "
            "values (%s, 'toxy-enricher', %s::jsonb, 1, true)",
            (reg, json.dumps({"sections": {"Press coverage": [item]}})),
        )
        mark = cur.execute(
            "select pf.checked_by, pf.source_level, pf.check_mark, pf.checked_on is not null "
            "from press_item_firms pf join press_items p on p.id = pf.press_item_id "
            "where pf.firm_id = %s and p.url = %s",
            (fid, item["url"]),
        ).fetchone()
        assert mark == ("Checker", 2, "checked_correct", True)
        conn.rollback()
