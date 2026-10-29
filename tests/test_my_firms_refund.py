"""My firms refund note: my_firms() gives refunded_at after a 24 h auto-refund, and drops it once the firm is opened again."""
import json
import os
import uuid

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
def test_refund_note():
    import psycopg

    uid = str(uuid.uuid4())
    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("insert into auth.users (id) values (%s)", (uid,))
        cur.execute("insert into firms (slug, name, published, data_status) values ('zz-rf', 'ZZ Rf', true, 'real') returning id")
        fid = cur.fetchone()[0]
        cur.execute("insert into check_balances (user_id) values (%s) returning id", (uid,))
        bid = cur.fetchone()[0]
        cur.execute("insert into research_queue (registry_id, name, priority) values ('zz-rf', 'ZZ Rf', 1)")
        cur.execute("insert into ondemand_jobs (firm_id, registry_id) values (%s, 'zz-rf') returning id", (fid,))
        jid = cur.fetchone()[0]
        cur.execute("insert into check_events (balance_id, firm_id, kind, amount) values (%s, %s, 'spend_free', 1)", (bid, fid))
        cur.execute("""insert into research_requests (job_id, firm_id, balance_id, user_id, spend_kind, created_at)
                       values (%s, %s, %s, %s, 'spend_free', now() - interval '25 hours')""", (jid, fid, bid, uid))
        cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (uid,))

        def row():
            cur.execute("select my_firms()")
            return [r for r in cur.fetchone()[0] if r["slug"] == "zz-rf"][0]

        assert row()["refunded_at"] is None  # still running: no note
        cur.execute("select ondemand_refund_expired()")
        r = row()
        assert r["refunded_at"] and r["checked_at"]  # refunded by the real 24 h job
        cur.execute("insert into check_events (balance_id, firm_id, kind, amount) values (%s, %s, 'spend_paid', 1)", (bid, fid))
        assert row()["refunded_at"] is None  # checked again: the note goes away
        conn.rollback()
