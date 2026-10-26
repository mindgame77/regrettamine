"""Step 2: items removed in a cleanup are fingerprinted and never re-added, even when slightly reworded."""
import json
import os
import uuid

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
DOCKET = "https://www.courtlistener.com/docket/67403514/ftx-trading-ltd/"
ADV = "https://adviserinfo.sec.gov/firm/summary/331435"
FTX = "FTX Trading Ltd. adversary 23-50380 (Bankr. D. Del.) and appeal 1:24-mc-00563, entities appear; role not reviewed"
NOTE = ("The US entity is SEC-registered; the London LLP and the Guernsey entity are SEC exempt reporting advisers. "
        "Both forms of SEC registration count as Clear.")


def _db():
    import psycopg
    return psycopg.connect(DATABASE_URL)


def _firm(c):
    slug = "removed-" + uuid.uuid4().hex[:8]
    fid = c.execute("insert into firms(slug, name, short_name, published, data_status, primary_domain) "
                    "values (%s, 'Removed Test', 'Rm', true, 'real', 'rm.test') returning id", (slug,)).fetchone()[0]
    c.execute("update ingest_settings set value = '1' where key = 'data_rules_from_enrichment_id'")
    c.execute("update ingest_settings set value = '1' where key = 'auto_promote_enrichment'")
    return slug, fid


def _enrich(c, p):
    r = c.execute("select research_enrich('toxy-enricher', %s::jsonb)", (json.dumps(p),)).fetchone()[0]
    return r if isinstance(r, dict) else json.loads(r)


def _remove(c, table, fid, like):
    rid = c.execute(f"select id from {table} where firm_id = %s and {'title' if table == 'firm_legal_items' else 'value'} ilike %s",
                    (fid, like)).fetchone()[0]
    assert c.execute("select record_removed(%s, %s, %s, 'test cleanup', 'pytest')", (table, rid, fid)).fetchone()[0]
    c.execute("delete from fact_sources where fact_id = %s", (rid,))
    c.execute(f"delete from {table} where id = %s", (rid,))


def _rejected(c, fid):
    return [r[0] for r in c.execute("select reason from publish_checks where firm_id = %s and outcome = 'rejected' "
                                    "and reason like 'matches removed item%%'", (fid,)).fetchall()]


def test_fingerprint_ignores_case_punctuation_quotes_dates():
    with _db() as c:
        one = lambda q, *a: c.execute(q, a).fetchone()[0]
        a = one("select _fp_text(%s)", "Lead (allegation, not verified): \"FTX\" Trading, Ltd. filed 2023-05-06")
        b = one("select _fp_text(%s)", "ftx trading ltd — filed May 6, 2023")
        assert a == b == "ftx trading ltd filed"
        assert one("select _fp_cases(%s)", "case 23-50380 and 1:24-mc-00563; SEC 801-114985") == ["23-50380", "24-mc-00563"]
        assert one("select _fp_url(%s)", "https://www.Example.com/a/?utm_source=x#top") == "example.com/a"


def test_reworded_lead_and_note_are_rejected():
    with _db() as c:
        slug, fid = _firm(c)
        _enrich(c, {"slug": slug, "sections": {
            "Legal & regulatory": [{"title": FTX, "allegation": True, "source": DOCKET}],
            "Overview": [{"label": "Registration", "value": NOTE, "source": ADV}]}})
        _remove(c, "firm_legal_items", fid, "%23-50380%")
        _remove(c, "firm_profile_facts", fid, "The US entity%")
        r = _enrich(c, {"slug": slug, "sections": {
            "Legal & regulatory": [{"title": "Y Combinator funds named in FTX Trading adversary proceeding no. 23-50380 (Delaware bankruptcy court)",
                                    "allegation": True, "date": "2024-01-10", "source": "https://www.reuters.com/ftx"}],
            "Overview": [{"label": "Registration", "value": "The U.S. entity is SEC registered; the London LLP and Guernsey entity are "
                          "SEC exempt reporting advisers. Both forms of registration count as \"Clear\".", "source": ADV},
                         {"label": "Founded", "value": "Founded in 1983 in Palo Alto", "source": ADV}]}})
        assert len(_rejected(c, fid)) == 2
        assert c.execute("select count(*) from firm_legal_items where firm_id = %s", (fid,)).fetchone()[0] == 0
        vals = [x[0] for x in c.execute("select value from firm_profile_facts where firm_id = %s", (fid,)).fetchall()]
        assert vals == ["Founded in 1983 in Palo Alto"]  # an unrelated fact cited to the same page still publishes
        c.rollback()


def test_record_removed_requires_reason_and_locks():
    with _db() as c:
        slug, fid = _firm(c)
        _enrich(c, {"slug": slug, "sections": {"Timeline": [{"date": "2010", "event": "Opened office", "source": ADV}]}})
        tid = c.execute("select id from timeline_events where firm_id = %s", (fid,)).fetchone()[0]
        import psycopg
        with pytest.raises(psycopg.errors.RaiseException):
            with c.transaction():
                c.execute("select record_removed('timeline_events', %s, %s, '  ')", (tid, fid))
        c.execute("select record_removed('timeline_events', %s, %s, 'wrong', 'pytest')", (tid, fid))
        assert c.execute("select _is_locked('timeline_events', %s, %s)", (tid, fid)).fetchone()[0]
        assert c.execute("select reason from removed_items where source_row_id = %s", (tid,)).fetchone()[0] == "wrong"
        c.rollback()
