"""Only toxy-enricher writes a public page. The queue, a visitor request, and a researcher upload do not."""
import json
import os
import uuid

import pytest

pytest.importorskip("psycopg")
import psycopg  # noqa: E402

DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
SRC = "https://www.sec.gov/enricher-only"
HAND = [
    "edit_in_place(text, uuid, uuid, jsonb, text, text)",
    "record_removed(text, uuid, uuid, text, text, boolean)",
    "restore_hidden(text, uuid, uuid, text)",
    "merge_firms(text, text, text)",
    "rename_firm_slug(text, text, text, text)",
]


def _j(v):
    return v if isinstance(v, (dict, list)) else json.loads(v)


def test_enricher_publishes_at_ingest_and_other_bots_do_not():
    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("update ingest_settings set value = '0' where key = 'auto_promote_enrichment'")
        cur.execute("select set_config('app.test_auto_publish', '', true)")
        assert cur.execute("select _auto_publish_on()").fetchone()[0] is False
        slug = "zz-eop-" + uuid.uuid4().hex[:8]
        fid = cur.execute(
            "insert into firms (slug, name, published, data_status, indexable) values (%s, 'Zz Eop', true, 'real', false) returning id",
            (slug,)).fetchone()[0]
        body = {"slug": slug, "sections": {"Timeline": [{"date": "2011", "event": "Opened a desk", "source": SRC}]}}
        got = _j(cur.execute("select research_enrich('toxy-enricher', %s::jsonb)", (json.dumps(body),)).fetchone()[0])
        assert got["valid"] is True and got["on_page"] is True
        assert cur.execute("select count(*) from timeline_events where firm_id = %s and hidden = false", (fid,)).fetchone()[0] == 1
        assert cur.execute("select indexable from firms where id = %s", (fid,)).fetchone()[0] is True
        other = _j(cur.execute("select research_enrich('zz-not-enricher', %s::jsonb)", (json.dumps(body),)).fetchone()[0])
        assert other["valid"] is True and other["on_page"] is False
        assert cur.execute(
            "select count(*) from publish_checks where origin = 'enrichment' and origin_id = %s and outcome in ('published', 'merged')",
            (other["enrichment_id"],)).fetchone()[0] == 0
        assert cur.execute("select count(*) from timeline_events where firm_id = %s and hidden = false", (fid,)).fetchone()[0] == 1
        conn.rollback()


def test_queue_and_request_do_not_create_a_firm():
    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("insert into research_queue (registry_id, name, priority, status) values ('zz-eop-q', 'Zz Eop Queue', 1, 'queued')")
        assert cur.execute("select count(*) from firms where registry_id = 'zz-eop-q'").fetchone()[0] == 0
        anon = str(uuid.uuid4())
        got = _j(cur.execute(
            "select request_firm('Zz Eop Requested Capital', 'zz-eop-req@example.com', null, %s)", (anon,)).fetchone()[0])
        assert got["status"] == "ok"
        rid = cur.execute(
            "select id, 'req-' || id from firm_requests where name_key = _queue_name_key('Zz Eop Requested Capital')").fetchone()
        assert cur.execute("select count(*) from firms where name = 'Zz Eop Requested Capital'").fetchone()[0] == 0
        assert cur.execute("select lane from research_queue where registry_id = %s", (rid[1],)).fetchone()[0] == "request"
        cur.execute("insert into research_queue (registry_id, name, priority, status) values ('zz-eop-link', 'Zz Eop Link', 1, 'queued')")
        linked = _j(cur.execute("select firm_request_link(%s, 'zz-eop-link')", (rid[0],)).fetchone()[0])
        assert linked["status"] == "ok" and linked["firm_id"] is None
        assert cur.execute("select count(*) from firms where registry_id = 'zz-eop-link'").fetchone()[0] == 0
        status, firm_id = cur.execute("select status, firm_id from firm_requests where id = %s", (rid[0],)).fetchone()
        assert status == "linked" and firm_id is None
        conn.rollback()


def test_researcher_batch_does_not_write_the_page():
    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        fid = cur.execute(
            "insert into firms (slug, name, published, data_status, indexable) values ('zz-eop-sub', 'Zz Eop Sub', true, 'real', false) returning id"
        ).fetchone()[0]
        before = cur.execute("select count(*) from firm_profile_facts where firm_id = %s", (fid,)).fetchone()[0]
        closed = _j(cur.execute("select _promote_submissions(%s)", (fid,)).fetchone()[0])
        assert closed["closed"] is True and closed["facts"] == 0 and closed["submission_id"] is None
        batch = "t-" + uuid.uuid4().hex[:6]
        cur.execute("select create_publish_batch(%s, 'submissions', null, %s::uuid[])", (batch, [str(fid)]))
        held = _j(cur.execute("select _publish_firm(%s, 'submissions', %s)", (batch, fid)).fetchone()[0])
        assert held["decision"] == "held"
        assert any("do not write" in r for r in held["reasons"])
        assert cur.execute("select count(*) from firm_profile_facts where firm_id = %s", (fid,)).fetchone()[0] == before
        conn.rollback()


def test_admin_cannot_write_firms_and_hand_tools_stay_on_the_service_key():
    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        uid = cur.execute(
            "insert into auth.users (id, email) values (gen_random_uuid(), %s) returning id",
            ("zz-eop-admin-" + uuid.uuid4().hex[:8] + "@example.com",)).fetchone()[0]
        cur.execute("update profiles set is_admin = true where id = %s", (uid,))
        cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (str(uid),))
        cur.execute("set role authenticated")
        cur.execute("savepoint admin_write")
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            cur.execute("insert into firms (slug, name, published, data_status) values ('zz-eop-admin', 'Nope', true, 'real')")
        cur.execute("rollback to savepoint admin_write")
        cur.execute("reset role")
        for fn in HAND:
            assert cur.execute("select has_function_privilege('anon', %s, 'execute')", ("public." + fn,)).fetchone()[0] is False
            assert cur.execute("select has_function_privilege('authenticated', %s, 'execute')", ("public." + fn,)).fetchone()[0] is False
            if cur.execute("select 1 from pg_roles where rolname = 'service_role'").fetchone():
                assert cur.execute("select has_function_privilege('service_role', %s, 'execute')", ("public." + fn,)).fetchone()[0] is True
        conn.rollback()
