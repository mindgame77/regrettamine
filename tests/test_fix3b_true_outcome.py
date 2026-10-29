"""Fix 3b: after each write the log records the true outcome. A row the one-home guard dropped is
logged 'blocked' with the guard's reason, never 'published'."""
import os

import pytest

pytest.importorskip("psycopg")
import psycopg  # noqa: E402

DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")


def _firm(cur, slug="zz-f3b"):
    return cur.execute("insert into firms (slug, name, published, data_status) values (%s, 'ZZ F3b', true, 'real') returning id",
                       (slug,)).fetchone()[0]


def test_pc_logs_blocked_for_dropped_row_and_published_for_saved_row():
    with psycopg.connect(DATABASE_URL) as c, c.cursor() as cur:
        fid = _firm(cur)
        a, b = [cur.execute("select gen_random_uuid()").fetchone()[0] for _ in range(2)]
        cur.execute("insert into firm_profile_facts (id, firm_id, section, label, value) values (%s, %s, 'funds', 'Regulatory AUM', 'RAUM 1,000,000,000 USD')", (a, fid))
        cur.execute("select public._pc(1, 'test', %s, 'funds', 'record', 'aum', '{}'::jsonb, 'published', null, 'firm_profile_facts', %s)", (fid, a))
        cur.execute("insert into firm_profile_facts (id, firm_id, section, label, value) values (%s, %s, 'overview', 'Headquarters', 'NYC')", (b, fid))
        cur.execute("select public._pc(1, 'test', %s, 'overview', 'record', 'hq', '{}'::jsonb, 'published', null, 'firm_profile_facts', %s)", (fid, b))
        rows = dict(cur.execute("select target_id, outcome || '|' || coalesce(reason, '') from publish_checks where target_id in (%s, %s)", (a, b)).fetchall())
        assert rows[a].startswith("blocked|One home per field (fix 3)")
        assert rows[b] == "published|"
        c.rollback()


def test_checker_place_reports_blocked():
    with psycopg.connect(DATABASE_URL) as c, c.cursor() as cur:
        fid = _firm(cur, "zz-f3b-2")
        r = cur.execute("select outcome, reason from public._checker_place(%s, 'overview', %s::jsonb, 'https://adviserinfo.sec.gov/x', 1::smallint, null, null)",
                        (fid, '{"label":"Regulatory AUM","value":"$46,000,000,000 USD"}')).fetchone()
        assert r[0] == "blocked" and r[1].startswith("One home per field (fix 3)")
        r = cur.execute("select outcome from public._checker_place(%s, 'overview', %s::jsonb, 'https://zz.example/about', 1::smallint, null, null)",
                        (fid, '{"label":"Headquarters","value":"NYC"}')).fetchone()
        assert r[0] == "published"
        c.rollback()


def test_old_log_rows_untouched_and_blocked_allowed():
    with psycopg.connect(DATABASE_URL) as c:
        d = c.execute("select pg_get_constraintdef(oid) from pg_constraint where conname = 'publish_checks_outcome_check'").fetchone()[0]
        assert "blocked" in d and "published" in d
