"""Step 1: research waits in the holding area, promote only adds, and locked rows are never touched."""
import json
import os
import uuid

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
SRC = "https://www.sec.gov/addonly"


def _db():
    import psycopg
    return psycopg.connect(DATABASE_URL)


def _firm(c, auto="1"):
    slug = "addonly-" + uuid.uuid4().hex[:8]
    fid = c.execute("insert into firms(slug, name, short_name, published, data_status, primary_domain) "
                    "values (%s, 'Add Only Test', 'Ao', true, 'real', 'ao.test') returning id", (slug,)).fetchone()[0]
    c.execute("update ingest_settings set value = '1' where key = 'data_rules_from_enrichment_id'")
    c.execute("update ingest_settings set value = %s where key = 'auto_promote_enrichment'", (auto,))
    return slug, fid


def _enrich(c, p):
    r = c.execute("select research_enrich('toxy-enricher', %s::jsonb)", (json.dumps(p),)).fetchone()[0]
    return r if isinstance(r, dict) else json.loads(r)


def _rows(c, fid):
    q = ("select 'f:'||id||value from firm_profile_facts where firm_id = %(f)s union all "
         "select 'l:'||id||title from firm_legal_items where firm_id = %(f)s union all "
         "select 'p:'||id||person_name||role from firm_people_roles where firm_id = %(f)s union all "
         "select 't:'||id||body from timeline_events where firm_id = %(f)s union all "
         "select 'x:'||press_item_id from press_item_firms where firm_id = %(f)s")
    return {r[0] for r in c.execute(q, {"f": fid}).fetchall()}


PAYLOAD = {"sections": {
    "Timeline": [{"date": "2009", "event": "Founded in Menlo Park", "source": SRC}],
    "People & board seats": [{"name": "Pat Example", "role": "General Partner", "source": SRC}]}}


def test_enricher_publishes_and_another_bot_stays_in_holding():
    with _db() as c:
        slug, fid = _firm(c, auto="0")
        c.execute("select set_config('app.test_auto_publish', '', true)")
        got = _enrich(c, dict(PAYLOAD, slug=slug))
        assert got["on_page"] is True
        assert len(_rows(c, fid)) == 2
        other = c.execute("select research_enrich('zz-other-bot', %s::jsonb)", (json.dumps(dict(PAYLOAD, slug=slug)),)).fetchone()[0]
        other = other if isinstance(other, dict) else json.loads(other)
        assert other["on_page"] is False
        assert c.execute(
            "select count(*) from publish_checks where origin = 'enrichment' and origin_id = %s and outcome in ('published', 'merged')",
            (other["enrichment_id"],)).fetchone()[0] == 0
        assert len(_rows(c, fid)) == 2
        c.rollback()


def test_repromote_deletes_nothing_and_dedupes():
    with _db() as c:
        slug, fid = _firm(c)
        _enrich(c, dict(PAYLOAD, slug=slug))
        first = _rows(c, fid)
        assert len(first) == 2
        # a later run that drops those items and repeats one must not remove or duplicate anything
        _enrich(c, {"slug": slug, "sections": {
            "Timeline": [{"date": "2009", "event": "Founded in Menlo Park", "source": "https://www.reuters.com/ao"},
                         {"date": "2015", "event": "Opened London office", "source": SRC}]}})
        second = _rows(c, fid)
        assert first <= second and len(second) == 3
        c.execute("select promote_enrichment(%s)", (fid,))
        assert _rows(c, fid) == second
        c.rollback()


def test_locked_rows_are_never_changed_or_readded():
    with _db() as c:
        slug, fid = _firm(c)
        _enrich(c, dict(PAYLOAD, slug=slug))
        pid, prole = c.execute("select id, role from firm_people_roles where firm_id = %s", (fid,)).fetchone()
        tid = c.execute("select id from timeline_events where firm_id = %s", (fid,)).fetchone()[0]
        c.execute("insert into locked_rows(table_name, row_id, firm_id, reason) values "
                  "('firm_people_roles', %s, %s, 'test'), ('timeline_events', %s, %s, 'test')", (pid, fid, tid, fid))
        src_before = c.execute("select count(*) from fact_sources where fact_id = %s", (pid,)).fetchone()[0]
        # a cleanup removes the locked timeline row; the same item must not come back
        c.execute("delete from fact_sources where fact_id = %s", (tid,))
        c.execute("delete from timeline_events where id = %s", (tid,))
        _enrich(c, dict(PAYLOAD, slug=slug, sections=dict(PAYLOAD["sections"], **{
            "People & board seats": [{"name": "Pat Example", "role": "General Partner", "source": "https://www.reuters.com/pat"}]})))
        assert c.execute("select count(*) from timeline_events where id = %s", (tid,)).fetchone()[0] == 0
        assert c.execute("select role from firm_people_roles where id = %s", (pid,)).fetchone()[0] == prole
        assert c.execute("select count(*) from fact_sources where fact_id = %s", (pid,)).fetchone()[0] == src_before
        c.rollback()


def test_lock_helpers():
    with _db() as c:
        rid, fid, other = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
        c.execute("insert into locked_rows(table_name, row_id, firm_id, reason) values ('firm_legal_items', %s, %s, 't')", (rid, fid))
        one = lambda q, *a: c.execute(q, a).fetchone()[0]
        assert one("select _is_locked('firm_legal_items', %s, %s)", rid, fid)
        assert not one("select _is_locked('firm_legal_items', %s, %s)", rid, other)
        assert not one("select _is_locked('timeline_events', %s, %s)", rid, fid)
        assert one("select _is_locked_any(%s, %s)", rid, fid)
        c.rollback()
