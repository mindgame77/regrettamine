"""'Checking this firm': queue bump, progress poll, and the email-me request."""
import json
import os
import uuid

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")


def _j(cur, sql, args):
    cur.execute(sql, args)
    v = cur.fetchone()[0]
    return v if isinstance(v, dict) else json.loads(v)


def test_bump_progress_and_notify():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("insert into firms (slug, name, published, launch_page, sec_crd) values ('zz-chk', 'Zz Check Capital', true, true, '999001') returning id")
        fid = cur.fetchone()[0]
        cur.execute("insert into firm_check_rows (firm_id, n, title, descr, state) select %s, n, 'T' || n, 'D', 'nc' from generate_series(1, 10) n", (fid,))
        cur.execute("insert into research_queue (registry_id, name, sec_crd, priority, status) values "
                    "('zz-1', 'ZZ CHECK CAPITAL LLC', '999001', 900000, 'queued'), ('zz-2', 'Other', null, 800000, 'queued'),"
                    " ('zz-3', 'Done Co', null, 5, 'submitted')")
        cur.execute("select min(priority) from research_queue where status = 'queued' and registry_id <> 'zz-1'")
        front = cur.fetchone()[0]
        a = str(uuid.uuid4())
        r = _j(cur, "select bump_firm_check('zz-chk', %s)", (a,))
        assert r.get("bumped") is True
        cur.execute("select priority from research_queue where registry_id = 'zz-1'")
        assert cur.fetchone()[0] == front - 1
        # same visitor again: rate limited, no change; another visitor: already at the front, no change (idempotent)
        assert _j(cur, "select bump_firm_check('zz-chk', %s)", (a,))["status"] == "rate_limited"
        r2 = _j(cur, "select bump_firm_check('zz-chk', %s)", (str(uuid.uuid4()),))
        assert r2.get("front") and not r2.get("bumped")
        cur.execute("select priority from research_queue where registry_id = 'zz-1'")
        assert cur.fetchone()[0] == front - 1
        # claimed: never touched
        cur.execute("update research_queue set status = 'claimed', priority = 900000 where registry_id = 'zz-1'")
        assert _j(cur, "select bump_firm_check('zz-chk', %s)", (str(uuid.uuid4()),))["status"] == "claimed"
        cur.execute("select priority, status from research_queue where registry_id = 'zz-1'")
        assert cur.fetchone() == (900000, "claimed")
        # claim takes the highest priority (lowest number) first
        cur.execute("update research_queue set status = 'queued', priority = -50 where registry_id = 'zz-1'")
        cur.execute("select registry_id from research_claim('t', 1)")
        assert cur.fetchone()[0] == "zz-1"

        # progress
        s = _j(cur, "select firm_check_status('zz-chk')", ())
        assert s["done"] == 0 and not s["complete"] and s["queue"] == "claimed"
        cur.execute("update firm_check_rows set state = 'clear' where firm_id = %s and n <= 3", (fid,))
        assert _j(cur, "select firm_check_status('zz-chk')", ())["done"] == 3

        # email request: stored, not ready until all 10 done, deduped
        assert _j(cur, "select notify_when_checked('zz-chk', 'bad', %s)", (a,))["status"] == "bad_email"
        assert _j(cur, "select notify_when_checked('zz-chk', 'Me@Example.com', %s)", (a,))["status"] == "ok"
        assert _j(cur, "select notify_when_checked('zz-chk', 'me@example.com', %s)", (a,))["status"] == "ok"
        cur.execute("select count(*) from check_requests where firm_id = %s", (fid,))
        assert cur.fetchone()[0] == 1
        cur.execute("select count(*) from ready_check_requests() where slug = 'zz-chk'")
        assert cur.fetchone()[0] == 0
        cur.execute("update firm_check_rows set state = 'clear' where firm_id = %s", (fid,))
        cur.execute("select email from ready_check_requests() where slug = 'zz-chk'")
        assert cur.fetchone()[0] == "me@example.com"
        assert _j(cur, "select bump_firm_check('zz-chk', %s)", (str(uuid.uuid4()),))["status"] == "complete"
        conn.rollback()
