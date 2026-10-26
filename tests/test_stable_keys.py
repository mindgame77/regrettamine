"""Step 5: stable keys merge instead of duplicating, last_checked_at on publish/re-confirm, per-section count alerts."""
import json
import os
import uuid

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
ADV = "https://adviserinfo.sec.gov/firm/summary/999005"
DOCKET = "https://www.courtlistener.com/docket/999005/keys/"


def _db():
    import psycopg
    return psycopg.connect(DATABASE_URL)


def _firm(c):
    slug = "keys-" + uuid.uuid4().hex[:8]
    fid = c.execute("insert into firms(slug, name, short_name, published, data_status, primary_domain) "
                    "values (%s, 'Keys Test', 'Kt', true, 'real', 'kt.test') returning id", (slug,)).fetchone()[0]
    c.execute("update ingest_settings set value = '1' where key in ('data_rules_from_enrichment_id', 'auto_promote_enrichment')")
    return slug, fid


def _submit(c, slug, sections):
    c.execute("select research_enrich('toxy-enricher', %s::jsonb)", (json.dumps({"slug": slug, "sections": sections}),))


def _n(c, t, fid):
    return c.execute(f"select count(*) from {t} where firm_id = %s", (fid,)).fetchone()[0]


def test_key_functions():
    with _db() as c:
        one = lambda q, *a: c.execute(q, a).fetchone()[0]
        assert one("select _person_key('Dr. Jane  Roe')") == one("select _person_key('jane roe')")
        assert one("select _legal_key('Doe v. Keys Capital, 3:24-cv-01234 (N.D. Cal.)')") == one("select _legal_key('Keys Capital sued, case 24-cv-01234')")
        assert one("select _legal_key('Doe v. Keys Capital (N.D. Cal.)')") == one("select _legal_key('Doe v. Keys Capital')")
        assert one("select _fund_key('Keys Fund II, L.P. · $100M · 2020')") == one("select _fund_key('Keys Fund II')")
        assert one("select _fund_key('Keys Fund II (021-123456)')") == "file:021-123456"
        assert one("select _timeline_key('2019-06', 'Raised Fund I')") == one("select _timeline_key('2019', 'Raised Fund I')")


def test_promote_merges_on_keys_and_sets_last_checked():
    with _db() as c:
        slug, fid = _firm(c)
        _submit(c, slug, {"People": [{"name": "Jane Roe", "role": "Partner", "source": ADV}],
                          "Legal & regulatory": [{"title": "Doe v. Keys Capital, 3:24-cv-01234 (N.D. Cal.)", "source": DOCKET}],
                          "Timeline": [{"date": "2019-06", "event": "Raised Fund I", "source": ADV}],
                          "Funds": [{"name": "Keys Fund II, L.P.", "source": ADV}]})
        base = {t: _n(c, t, fid) for t in ("firm_people_roles", "firm_legal_items", "timeline_events", "firm_profile_facts")}
        assert base == {"firm_people_roles": 1, "firm_legal_items": 1, "timeline_events": 1, "firm_profile_facts": 1}, base
        first = c.execute("select last_checked_at, checked_source from timeline_events where firm_id = %s", (fid,)).fetchone()
        assert first[0] is not None and first[1] == ADV
        _submit(c, slug, {"People": [{"name": "Dr. Jane Roe", "role": "Partner", "source": ADV + "/2"}],
                          "Legal & regulatory": [{"title": "Keys Capital sued in 24-cv-01234", "source": DOCKET + "2/"}],
                          "Timeline": [{"date": "2019", "event": "Raised Fund I.", "source": ADV + "/2"}],
                          "Funds": [{"name": "Keys Fund II", "source": ADV + "/2"}]})
        assert {t: _n(c, t, fid) for t in base} == base  # merged, nothing added
        assert c.execute("select checked_source from timeline_events where firm_id = %s", (fid,)).fetchone()[0] == ADV + "/2"
        assert c.execute("select count(*) from publish_checks where firm_id = %s and outcome = 'merged'", (fid,)).fetchone()[0] == 4
        c.rollback()


def test_existing_rows_have_null_last_checked_and_collisions_are_only_reported():
    with _db() as c:
        slug, fid = _firm(c)
        for _ in range(2):
            c.execute("insert into timeline_events(id, firm_id, date_label, kind, body, sort_order) "
                      "values (gen_random_uuid(), %s, '2010', 'Reported', 'Opened office', 1)", (fid,))
        assert c.execute("select count(*) from timeline_events where firm_id = %s and last_checked_at is null", (fid,)).fetchone()[0] == 2
        col = c.execute("select n from stable_key_collisions() where firm_id = %s and tbl = 'timeline_events'", (fid,)).fetchone()
        assert col == (2,)
        assert _n(c, "timeline_events", fid) == 2
        c.rollback()


def test_section_count_alerts():
    with _db() as c:
        slug, fid = _firm(c)
        _submit(c, slug, {"Timeline": [{"date": str(2000 + i), "event": f"Event number {i}", "source": ADV} for i in range(2)]})
        assert c.execute("select count(*) from section_count_alerts where firm_id = %s", (fid,)).fetchone()[0] == 0  # first: baseline
        _submit(c, slug, {"Timeline": [{"date": "2010", "event": "Event number ten", "source": ADV}]})  # 2 -> 3 (+50%, not more)
        assert c.execute("select count(*) from section_count_alerts where firm_id = %s", (fid,)).fetchone()[0] == 0
        _submit(c, slug, {"Timeline": [{"date": str(2011 + i), "event": f"Later event {i}", "source": ADV} for i in range(2)]})  # 3 -> 5
        tid = c.execute("select id from timeline_events where firm_id = %s limit 1", (fid,)).fetchone()[0]
        c.execute("update timeline_events set hidden = true where id = %s", (tid,))  # not recorded: a real drop
        _submit(c, slug, {"Overview": [{"label": "Founded", "value": "1999", "source": ADV}]})  # timeline 5 -> 4: drop
        got = c.execute("select section, prev_n, new_n, kind from section_count_alerts where firm_id = %s order by id", (fid,)).fetchall()
        assert got == [("timeline", 3, 5, "jump"), ("timeline", 5, 4, "drop")], got
        c.rollback()


def test_recorded_hide_or_replace_does_not_raise_a_drop_alert():
    with _db() as c:
        slug, fid = _firm(c)
        _submit(c, slug, {"Timeline": [{"date": str(2000 + i), "event": f"Event number {i}", "source": ADV} for i in range(3)]})
        alerts = lambda: c.execute("select section, prev_n, new_n, kind from section_count_alerts where firm_id = %s order by id", (fid,)).fetchall()
        # replace: add the clean item, then hide the old one with a reason
        _submit(c, slug, {"Timeline": [{"date": "2010", "event": "Clean replacement event", "source": ADV}]})
        old = c.execute("select id from timeline_events where firm_id = %s and body = 'Event number 0'", (fid,)).fetchone()[0]
        c.execute("select record_removed('timeline_events', %s, %s, 'replaced by clean item', 'pytest', true)", (old, fid))
        assert c.execute("select n from section_counts where firm_id = %s and section = 'timeline'", (fid,)).fetchone()[0] == 3
        _submit(c, slug, {"Overview": [{"label": "Founded", "value": "1999", "source": ADV}]})
        assert alerts() == [], alerts()
        # restore is also snapshotted
        c.execute("select restore_hidden('timeline_events', %s, %s, 'pytest')", (old, fid))
        assert c.execute("select n from section_counts where firm_id = %s and section = 'timeline'", (fid,)).fetchone()[0] == 4
        _submit(c, slug, {"Overview": [{"label": "Founded", "value": "1999", "source": ADV}]})
        assert alerts() == [], alerts()
        c.rollback()
