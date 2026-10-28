"""Checker switch stays off. The reply points at the page guide. A dry run does not keep rows."""
import json
import os
import uuid

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")


def _db():
    import psycopg
    return psycopg.connect(DATABASE_URL)


def test_switch_file_leaves_the_enricher_path_in_place():
    from pathlib import Path
    sql = Path("supabase/migrations/20261028070000_checker_switch.sql").read_text(encoding="utf-8")
    assert "values ('checker_publish', 'false')" in sql
    assert "docs/PAGE_DATA_GUIDE.md" in sql
    assert "perform promote_enrichment(new.firm_id)" in sql
    assert "OpenSanctions is only a source inside checks 1, 2 and 10" in sql


def test_switch_is_off_and_levels_and_dry_run_roll_back():
    with _db() as c:
        assert c.execute("select _checker_publish_on()").fetchone()[0] is False
        fid = c.execute("select id from firms where slug = 'a16z' and deleted_at is null").fetchone()
        firm = fid[0] if fid else None
        sec = c.execute("select _source_level(%s, %s, null)", ("https://www.sec.gov/Archives/edgar/data/1/x.htm", firm)).fetchone()[0]
        assert sec == 1
        chat = c.execute("select _source_level(%s, %s, null)", ("https://www.google.com/search?q=a16z", firm)).fetchone()[0]
        assert chat is None
        blocked = c.execute("select _source_level(%s, %s, 4)", ("https://www.opensanctions.org/entities/x", firm)).fetchone()[0]
        assert blocked is None
        allowed = c.execute("select _source_level(%s, %s, 1)", ("https://www.opensanctions.org/entities/x", firm)).fetchone()[0]
        assert allowed == 1
        slug = "lab-checker-" + uuid.uuid4().hex[:8]
        c.execute("insert into firms(slug, name, short_name, hq, primary_domain, published, data_status) "
                  "values (%s, 'Checker Lab', 'CL', 'Palo Alto, CA', 'checker.example', true, 'real')", (slug,))
        c.execute("insert into ingest_settings(key, value) values ('lab_firm_slugs', %s) "
                  "on conflict (key) do update set value = excluded.value", (slug,))
        before = c.execute("select count(*) from firms").fetchone()[0]
        raw = c.execute("select checker_dry_run(%s)", (slug,)).fetchone()[0]
        report = raw if isinstance(raw, dict) else json.loads(raw)
        assert report["dry_run"] is True and report["switch"] is False
        assert report["published"] == 0
        assert c.execute("select count(*) from firms").fetchone()[0] == before
        assert c.execute("select count(*) from checker_marks m join firms f on f.id = m.firm_id where f.slug = %s", (slug,)).fetchone()[0] == 0
        other = c.execute("select checker_dry_run('not-a-lab-firm')").fetchone()[0]
        other = other if isinstance(other, dict) else json.loads(other)
        assert other["error"] == "unknown firm"
        fid = c.execute("select id from firms where slug = %s", (slug,)).fetchone()[0]
        def decide(section, url, item, probes=None):
            row = c.execute(
                "select outcome, lvl, reason from _checker_decide(%s, %s, %s::jsonb, %s, null, %s::jsonb)",
                (fid, section, json.dumps(item), url, json.dumps(probes) if probes is not None else None),
            ).fetchone()
            return row[0], row[1], row[2]
        assert decide("press", "https://techcrunch.com/story", {"headline": "Checker Lab raises a fund"})[0] == "published"
        assert decide("press", "https://example.com/blog", {"headline": "Checker Lab raises a fund"})[0] == "unconfirmed"
        assert decide("press", "https://techcrunch.com/story", {"headline": "Someone else raises"})[0] == "failure"
        assert decide("founders", "https://x.com/ada/status/1", {"who": "anonymous", "quote": "Checker Lab is fine"})[0] == "unconfirmed"
        assert decide("founders", "https://www.linkedin.com/in/ada", {"who": "Ada, founder", "quote": "Checker Lab led our round"})[0] == "published"
        assert decide("legal", "https://www.courtlistener.com/docket/1/x/", {"title": "X v Checker Lab"})[:2] == ("published", 1)
        assert decide("people", "https://www.linkedin.com/posts/ada_x", {"name": "Ada"})[0] == "unconfirmed"
        assert decide("people", "https://www.linkedin.com/in/ada", {"name": "Ada"})[:2] == ("published", 2)
        assert decide("deals", "https://www.sec.gov/Archives/edgar/data/1/formd.xml", {"company": "Acme"})[:2] == ("published", 2)
        assert decide("social", "https://x.com/checkerlab", {})[0] == "unconfirmed"
        assert decide("social", "https://checker.example/about", {})[:2] == ("published", 2)
        assert decide("press", "https://techcrunch.com/story", {"headline": "Checker Lab raises"}, {"https://techcrunch.com/story": False})[0] == "failure"
        c.rollback()
