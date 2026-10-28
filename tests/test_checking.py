"""'Checking this firm': no bump on page view, request-form bump, progress poll, and the email-me request."""
import json
import os
import uuid

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = [pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set"), pytest.mark.skip(reason="checks are off (Alex 2026-10-28): firm_check_rows is no longer filled")]


def _j(cur, sql, args):
    cur.execute(sql, args)
    v = cur.fetchone()[0]
    return v if isinstance(v, dict) else json.loads(v)


def test_bump_progress_and_notify():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("insert into firms (slug, name, published, launch_page, data_status, sec_crd) values ('zz-chk', 'Zz Check Capital', true, true, 'real', '999001') returning id")
        fid = cur.fetchone()[0]
        cur.execute("insert into firm_check_rows (firm_id, n, title, descr, state) select %s, n, 'T' || n, 'D', 'nc' from generate_series(1, 10) n", (fid,))
        cur.execute("insert into research_queue (registry_id, name, sec_crd, priority, status) values "
                    "('zz-1', 'ZZ CHECK CAPITAL LLC', '999001', 900000, 'queued'), ('zz-2', 'Other', null, 800000, 'queued'),"
                    " ('zz-3', 'Done Co', null, 5, 'submitted')")
        cur.execute("select min(priority) from research_queue where status = 'queued' and registry_id <> 'zz-1'")
        front = cur.fetchone()[0]
        a = str(uuid.uuid4())
        # page views (people and crawlers) never reorder the queue
        for _ in range(3):
            r = _j(cur, "select bump_firm_check('zz-chk', %s)", (str(uuid.uuid4()),))
            assert r["status"] == "queued" and not r.get("bumped")
        cur.execute("select priority from research_queue where registry_id = 'zz-1'")
        assert cur.fetchone()[0] == 900000
        # the request-a-check form naming the firm files a paid-lane job and moves it to the front
        cur.execute("select request_check('zz check capital', null, %s)", (a,))
        cur.execute("select priority, lane from research_queue where registry_id = 'zz-1'")
        assert cur.fetchone() == (front - 1, "paid")
        cur.execute("select request_check('nobody we know', null, %s)", (a,))
        cur.execute("select priority, lane from research_queue where registry_id = 'zz-1'")
        assert cur.fetchone() == (front - 1, "paid")
        reg = cur.execute("select registry_id from research_queue where list_source = 'check_request' and name = 'nobody we know'").fetchone()[0]
        assert reg.startswith("req-")
        assert cur.execute("select lane from research_queue where registry_id = %s", (reg,)).fetchone()[0] == "request"
        # claim takes the highest priority (lowest number) first; other bots never see the paid lane
        cur.execute("update research_queue set status = 'queued', lane = 'normal', priority = -50 where registry_id = 'zz-1'")
        cur.execute("select registry_id from research_claim('t', 1)")
        assert cur.fetchone()[0] == "zz-1"

        # progress
        s = _j(cur, "select firm_check_status('zz-chk')", ())
        assert s["done"] == 0 and not s["complete"] and s["queue"] == "claimed"
        cur.execute("update firm_check_rows set state = 'clear' where firm_id = %s and n <= 3", (fid,))
        assert _j(cur, "select firm_check_status('zz-chk')", ())["done"] == 3

        # email request: attached to the open paid job, not a second signup, not mailed until the job is done
        assert _j(cur, "select notify_when_checked('zz-chk', 'bad', %s)", (a,))["status"] == "bad_email"
        assert _j(cur, "select notify_when_checked('zz-chk', 'Me@Example.com', %s)", (a,))["status"] == "ok"
        assert _j(cur, "select notify_when_checked('zz-chk', 'me@example.com', %s)", (a,))["status"] == "ok"
        cur.execute("select count(*) from check_requests where firm_id = %s and email is not null", (fid,))
        assert cur.fetchone()[0] == 0
        cur.execute("select lower(email), spend_kind from research_requests where firm_id = %s", (fid,))
        assert cur.fetchone() == ("me@example.com", "request")
        cur.execute("select count(*) from ready_check_requests() where slug = 'zz-chk'")
        assert cur.fetchone()[0] == 0
        cur.execute("select count(*) from ondemand_outbox(50) o join research_requests r on r.id = o.id where r.firm_id = %s", (fid,))
        assert cur.fetchone()[0] == 0
        cur.execute("update firm_check_rows set state = 'clear' where firm_id = %s", (fid,))
        cur.execute("update ondemand_jobs set status = 'done', done_at = now() where firm_id = %s", (fid,))
        cur.execute("update research_requests set status = 'done', done_at = now() where firm_id = %s", (fid,))
        cur.execute("select o.kind, o.email from ondemand_outbox(50) o join research_requests r on r.id = o.id where r.firm_id = %s", (fid,))
        assert cur.fetchone() == ("ready", "me@example.com")
        cur.execute("select count(*) from ready_check_requests() where slug = 'zz-chk'")
        assert cur.fetchone()[0] == 0
        assert _j(cur, "select bump_firm_check('zz-chk', %s)", (str(uuid.uuid4()),))["status"] == "complete"
        conn.rollback()


def test_expired_normal_claim_is_not_shown_as_checking():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("insert into firms (slug, name, published, launch_page, data_status, sec_crd) values ('zz-exp', 'Zz Expired Capital', true, true, 'real', '999441') returning id")
        fid = cur.fetchone()[0]
        cur.execute("insert into firm_check_rows (firm_id, n, title, descr, state) select %s, n, 'T' || n, 'D', 'nc' from generate_series(1, 10) n", (fid,))
        cur.execute("insert into research_queue (registry_id, name, sec_crd, priority, status, lane, claimed_by, claimed_at, last_error) values "
                    "('zz-exp', 'ZZ EXPIRED CAPITAL LLC', '999441', 900000, 'claimed', 'normal', 'portal-night-bot-2', now() - interval '7 hours', 'gap-fill claim')")
        cur.execute("update firms set registry_id = 'zz-exp' where id = %s", (fid,))
        anon = str(uuid.uuid4())

        def status():
            return _j(cur, "select firm_check_status('zz-exp')", ())

        def page():
            return _j(cur, "select firm_page('zz-exp', %s, false, null)", (anon,))

        s = status()
        assert s["queue"] == "queued" and s["started_at"] is None
        p = page()
        assert p["queue"] == "queued" and p["started_at"] is None
        cur.execute("select status, claimed_by from research_queue where registry_id = 'zz-exp'")
        assert cur.fetchone() == ("claimed", "portal-night-bot-2")

        cur.execute("update research_queue set claimed_at = now() where registry_id = 'zz-exp'")
        s = status()
        assert s["queue"] == "claimed" and s["started_at"]
        assert page()["queue"] == "claimed" and page()["started_at"]

        cur.execute("update research_queue set lane = 'paid', claimed_at = now() - interval '7 hours' where registry_id = 'zz-exp'")
        s = status()
        assert s["queue"] == "claimed" and s["started_at"]

        cur.execute("update research_queue set lane = 'normal' where registry_id = 'zz-exp'")
        cur.execute("insert into ondemand_jobs (firm_id, registry_id, status) values (%s, 'zz-exp', 'queued')", (fid,))
        s = status()
        assert s["queue"] == "claimed" and s["started_at"]
        cur.execute("select status from research_queue where registry_id = 'zz-exp'")
        assert cur.fetchone()[0] == "claimed"
        conn.rollback()
