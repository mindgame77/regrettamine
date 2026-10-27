"""One switch. lock_enabled false opens the firm page and the report without spending a credit.
lock_enabled true is today's lock."""
import json
import os
import uuid

import pytest

pytest.importorskip("psycopg")
import psycopg  # noqa: E402

DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")


def _j(row):
    v = row[0]
    return v if isinstance(v, dict) else json.loads(v)


def test_lock_off_returns_full_pages_and_spends_nothing():
    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("select to_regclass('public.app_settings')")
        if cur.fetchone()[0] is None:
            pytest.skip("lock switch migration is not applied")
        cur.execute(
            "insert into firms (slug, name, published, indexable, data_status) "
            "values ('zz-lock', 'Zz Lock Capital', true, true, 'real') returning id"
        )
        fid = cur.fetchone()[0]
        cur.execute(
            "insert into firm_check_rows (firm_id, n, title, descr, state) values (%s, 1, 'Lawsuits', 'Court cases', 'nc')",
            (fid,),
        )
        cur.execute(
            """insert into firm_legal_items (firm_id, grp, title, year_label, state, note, sort_order)
               values (%s, 'case', 'Example v. Zz Lock', '2024', 'Active', 'A public case.', 0) returning id""",
            (fid,),
        )
        item = cur.fetchone()[0]
        cur.execute(
            "insert into sources (url, retrieved_at, data_status) values ('https://example.com/zz-lock-case', now(), 'real') "
            "on conflict (url) do update set url = excluded.url returning id"
        )
        sid = cur.fetchone()[0]
        cur.execute(
            """insert into fact_sources (source_id, firm_id, fact_type, fact_id, label, sort_order, data_status)
               values (%s, %s, 'firm_legal_items', %s, 'Example', 0, 'real')""",
            (sid, fid, item),
        )
        cur.execute(
            """insert into press_items (headline, url, published_label, publisher, data_status, retrieved_at, snippet)
               values ('Zz Lock raises a fund', 'https://example.com/zz-lock-press', '2026-01-02', 'Example', 'real', now(), 'A story')
               returning id"""
        )
        pid = cur.fetchone()[0]
        cur.execute(
            """insert into press_item_firms (press_item_id, firm_id, sort_order, check_mark)
               values (%s, %s, 0, 'checked_correct')""",
            (pid, fid),
        )
        cur.execute(
            "insert into report_pages (slug, html) values ('zz-lock', '<article data-report-body=\"zz-lock\">full report</article>')"
        )
        anon = str(uuid.uuid4())

        cur.execute("update public.app_settings set value = 'false' where key = 'lock_enabled'")
        assert cur.execute("select public.lock_enabled()").fetchone()[0] is False

        cur.execute("select count(*) from check_events where firm_id = %s", (fid,))
        spent_before = cur.fetchone()[0]
        cur.execute("select count(*) from report_views where firm_id = %s", (fid,))
        views_before = cur.fetchone()[0]

        cur.execute("select firm_page('zz-lock', %s, true)", (anon,))
        opened = _j(cur.fetchone())
        assert opened["status"] == "ok" and opened["open"] is True
        assert opened["details"] is not None
        assert opened["checks"][0]["state"] == "nc"
        assert isinstance(opened["checks"][0]["items"], list)
        keys = {s["key"] for s in opened["sections"]}
        assert "legal" in keys and "press" in keys
        legal = next(s for s in opened["sections"] if s["key"] == "legal")
        press = next(s for s in opened["sections"] if s["key"] == "press")
        assert legal["items"][0]["head"] == "Example v. Zz Lock"
        assert press["items"][0]["head"] == "Zz Lock raises a fund"

        cur.execute("select firm_activity_list('zz-lock', null, 'deals')")
        activity = _j(cur.fetchone())
        assert activity["status"] == "ok" and activity["items"] == []

        cur.execute("select open_report('zz-lock', null)")
        report = _j(cur.fetchone())
        assert report["ok"] is True and "full report" in report["html"]

        cur.execute("select count(*) from check_events where firm_id = %s", (fid,))
        assert cur.fetchone()[0] == spent_before
        cur.execute("select count(*) from report_views where firm_id = %s", (fid,))
        assert cur.fetchone()[0] == views_before
        cur.execute("select has_table_privilege('anon', 'public.app_settings', 'select')")
        assert cur.fetchone()[0] is False

        cur.execute("update public.app_settings set value = 'true' where key = 'lock_enabled'")
        assert cur.execute("select public.lock_enabled()").fetchone()[0] is True
        cur.execute("select firm_page('zz-lock', %s, false)", (anon,))
        locked = _j(cur.fetchone())
        assert locked["status"] == "ok" and locked["open"] is False
        assert locked["sections"] == [] and locked["details"] is None
        assert locked["checks"][0]["state"] is None and locked["checks"][0]["items"] is None
        cur.execute("select firm_activity_list('zz-lock', %s, 'deals')", (anon,))
        assert _j(cur.fetchone())["status"] == "locked"
        cur.execute("select open_report('zz-lock', null)")
        gated = _j(cur.fetchone())
        assert gated["ok"] is False and gated["reason"] == "anon"
        cur.execute("select count(*) from check_events where firm_id = %s", (fid,))
        assert cur.fetchone()[0] == spent_before

        cur.execute("select firm_page('zz-lock', %s, true)", (anon,))
        paid = _j(cur.fetchone())
        assert paid["open"] is True
        cur.execute(
            "select kind, amount from check_events where firm_id = %s",
            (fid,),
        )
        assert cur.fetchone() == ("spend_free", -1)
        conn.rollback()
