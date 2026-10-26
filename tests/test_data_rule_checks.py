"""Step 4: docs/DATA_RULES.md runs inside every promote path; a bad item stays in the holding area, logged as rejected."""
import json
import os
import uuid

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
ADV = "https://adviserinfo.sec.gov/firm/summary/999002"
DOCKET = "https://www.courtlistener.com/docket/999002/rules-test/"

BAD = {  # rule -> (section, item, table that must stay empty for it)
    "date": ("Timeline", {"date": "sometime in spring", "event": "Opened Austin office", "source": ADV}),
    "note": ("Overview", {"label": "Offices", "value": "3 searches run, awaiting review", "source": ADV}),
    "source": ("Timeline", {"date": "2001", "event": "Opened Boston office"}),
    "lead": ("Legal & regulatory", {"title": "Rules Test v. Lead Corp, 25-cv-04321 (D. Del.)", "allegation": True, "source": DOCKET}),
    "person": ("People", {"name": "Partners include Jane Roe and John Doe", "role": "Partner", "source": ADV}),
}
CLEAN = {"Timeline": [{"date": "1999-05", "event": "Firm founded", "source": ADV},
                      {"date": "May–Jul 2025", "event": "Raised fund two", "source": ADV}]}


def _db():
    import psycopg
    return psycopg.connect(DATABASE_URL)


def _firm(c):
    slug = "rules-" + uuid.uuid4().hex[:8]
    fid = c.execute("insert into firms(slug, name, short_name, published, data_status, primary_domain) "
                    "values (%s, 'Rules Test', 'Rt', true, 'real', 'rt.test') returning id", (slug,)).fetchone()[0]
    c.execute("update ingest_settings set value = '1' where key = 'data_rules_from_enrichment_id'")
    c.execute("update ingest_settings set value = '1' where key = 'auto_promote_enrichment'")
    return slug, fid


def _submit(c, slug, sections):
    c.execute("select research_enrich('toxy-enricher', %s::jsonb)", (json.dumps({"slug": slug, "sections": sections}),))


def _live(c, fid):
    return sum(c.execute(f"select count(*) from {t} where firm_id = %s", (fid,)).fetchone()[0]
               for t in ("firm_profile_facts", "firm_legal_items", "timeline_events", "firm_people_roles"))


@pytest.mark.parametrize("rule", sorted(BAD))
def test_one_bad_item_per_rule_is_rejected(rule):
    with _db() as c:
        slug, fid = _firm(c)
        sec, item = BAD[rule]
        _submit(c, slug, {sec: [item]})
        assert _live(c, fid) == 0
        reasons = [r[0] for r in c.execute("select reason from publish_checks where firm_id = %s and outcome = 'rejected'",
                                           (fid,)).fetchall()]
        assert reasons, rule
        if rule in ("note", "lead"):  # date, source and list-of-names are also caught by the older format checks first
            assert any(r.startswith(rule + ":") for r in reasons), reasons
        c.rollback()


def test_duplicate_is_merged_not_added_twice():
    with _db() as c:
        slug, fid = _firm(c)
        _submit(c, slug, CLEAN)
        _submit(c, slug, {"Timeline": [{"date": "1999-05", "event": "Firm founded", "source": ADV + "/b"}]})
        assert c.execute("select count(*) from timeline_events where firm_id = %s", (fid,)).fetchone()[0] == 2
        c.rollback()


def test_clean_items_are_accepted_and_report_is_read_only():
    with _db() as c:
        slug, fid = _firm(c)
        _submit(c, slug, CLEAN)
        assert c.execute("select count(*) from timeline_events where firm_id = %s", (fid,)).fetchone()[0] == 2
        assert c.execute("select count(*) from publish_checks where firm_id = %s and outcome = 'rejected'", (fid,)).fetchone()[0] == 0
        assert c.execute("select count(*) from data_rules_report() where firm_id = %s", (fid,)).fetchone()[0] == 0
        c.rollback()


def test_rule_function_cases():
    with _db() as c:
        r = lambda *a: c.execute("select _data_rule(%s, %s, %s::jsonb, %s)", (a[0], a[1], json.dumps(a[2]), a[3])).fetchone()[0]
        assert r("overview", "add", {"label": "Lead investor", "value": "Led the seed round of Stripe"}, ADV) is None
        assert r("overview", "add", {"label": "HQ", "value": "Lead (unverified): Palo Alto"}, ADV).startswith("lead:")
        assert r("overview", "add", {"label": "HQ", "value": "Friend-bot submission"}, ADV).startswith("note:")
        assert r("overview", "add", {"label": "HQ", "value": "x" * 301}, ADV).startswith("note:")
        assert r("timeline", "add", {"date": "2024-09-24/25", "event": "Event"}, ADV) is None
        assert r("timeline", "add", {"date": "Sept 2024", "event": "Event"}, ADV).startswith("date:")
        assert r("legal", "add", {"title": "A v. B", "date": "2024-1"}, ADV).startswith("date:")
        assert r("timeline", "add", {"date": "2024", "event": "Raised in March 2024 a new fund"}, ADV) is None
        assert r("people", "add", {"name": "Jane Roe", "role": "Partner"}, ADV) is None
        assert r("people", "add", {"name": "she joined from Google in 2019.", "role": "Partner"}, ADV).startswith("person:")
        assert r("overview", "add", {"label": "HQ", "value": "Palo Alto"}, None).startswith("source:")
