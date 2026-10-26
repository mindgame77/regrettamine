"""docs/DATA_RULES.md: bots send one structured item per fact; one checker decides at publish."""
import json
import os
import pathlib
import uuid

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = "https://www.sec.gov/a16z"
A16Z_SENTENCE = ("Bot audit: Schedule A records 14 individuals; related persons: Marc Andreessen and Ben Horowitz "
                 "match the schedule (log entry, no source url)")


def _db():
    import psycopg
    return psycopg.connect(DATABASE_URL)


def _firm(c, tag):
    slug = tag + "-" + uuid.uuid4().hex[:8]
    fid = c.execute("insert into firms(slug, name, short_name, published, data_status, primary_domain) "
                    "values (%s, 'Rules Test', 'Rt', true, 'real', 'rt.test') returning id", (slug,)).fetchone()[0]
    c.execute("update ingest_settings set value = '1' where key = 'data_rules_from_enrichment_id'")
    return slug, fid


def _enrich(c, p):
    r = c.execute("select research_enrich('toxy-enricher', %s::jsonb)", (json.dumps(p),)).fetchone()[0]
    return r if isinstance(r, dict) else json.loads(r)


def test_note_detector():
    with _db() as c:
        bad = lambda t, m=300: c.execute("select _note_text(%s, %s)", (t, m)).fetchone()[0]
        name = lambda t: c.execute("select _person_name_bad(%s)", (t,)).fetchone()[0]
        assert bad(A16Z_SENTENCE) and bad("see https://x.com/a") and bad("x" * 301)
        assert bad("General Partner") is None and bad("Headquarters: Menlo Park") is None
        assert name("Marc Andreessen") is None and name("Martin Luther King, Jr.") is None
        for n in ["Marc Andreessen and Ben Horowitz", "Schedule A (14)", "Smith, John", A16Z_SENTENCE, "", None]:
            assert name(n), n


def test_free_text_is_rejected_notes_are_kept_structured_is_published():
    with _db() as c:
        slug, fid = _firm(c, "dr")
        r = _enrich(c, {"slug": slug, "sections": {
            "People & board seats": [{"item": A16Z_SENTENCE, "source": SRC},
                                     {"name": A16Z_SENTENCE, "role": "Partner", "source": SRC},
                                     {"name": "Marc Andreessen", "role": "General Partner", "since": "2009", "source": SRC},
                                     {"note": "Schedule A lists 14 people; only 2 confirmed"}],
            "Timeline": [{"date": "2009-06", "event": "Founded", "source": SRC}, {"date": "June 2009", "event": "x", "source": SRC}]}})
        assert r["accepted_items"] == 2 and r["notes_kept"] == 1 and r["rejected_items"] == 3
        assert any("free text" in x["reason"] for x in r["rejected"])
        people = c.execute("select _sec_items('people', %s)", (fid,)).fetchone()[0]
        assert [x["head"] for x in people if "Andreessen" in x["head"]] == ["Marc Andreessen"]
        assert not any("Schedule" in json.dumps(x) for x in people)
        out = dict(c.execute("select outcome, count(*) from publish_checks where firm_id = %s group by 1", (fid,)).fetchall())
        assert out == {"published": 2, "note": 1, "rejected": 3}
        c.rollback()


def test_duplicate_merges_source_and_role_conflict_is_flagged():
    with _db() as c:
        slug, fid = _firm(c, "drm")
        pid = c.execute("insert into firm_people_roles(id, firm_id, person_name, role, kind) "
                        "values (gen_random_uuid(), %s, 'Ben Horowitz', 'General Partner', 'officer') returning id", (fid,)).fetchone()[0]
        r = _enrich(c, {"slug": slug, "sections": {"People & board seats": [
            {"name": "Ben Horowitz", "role": "General Partner", "source": "https://www.sec.gov/ben"},
            {"name": "ben horowitz", "role": "Chairman", "source": "https://www.reuters.com/ben"}]}})
        assert r["outcomes"] == {"merged": 1, "conflict": 1}
        assert c.execute("select count(*) from firm_people_roles where firm_id = %s", (fid,)).fetchone()[0] == 1
        assert c.execute("select role from firm_people_roles where id = %s", (pid,)).fetchone()[0] == "General Partner"
        assert c.execute("select count(*) from fact_sources f join sources s on s.id = f.source_id "
                         "where f.fact_id = %s and s.url = 'https://www.sec.gov/ben'", (pid,)).fetchone()[0] == 1
        # re-promote is add-only (step 1): the person and the source it added both stay
        _enrich(c, {"slug": slug, "sections": {"Timeline": [{"date": "2009", "event": "Founded", "source": SRC}]}})
        assert c.execute("select count(*) from fact_sources where fact_id = %s", (pid,)).fetchone()[0] == 1
        assert c.execute("select count(*) from firm_people_roles where id = %s", (pid,)).fetchone()[0] == 1
        c.rollback()


def test_old_format_rows_go_through_the_same_rules():
    with _db() as c:
        slug, fid = _firm(c, "drl")
        c.execute("update ingest_settings set value = '999999999' where key = 'data_rules_from_enrichment_id'")
        c.execute("select research_enrich('toxy-enricher', %s::jsonb)",
                  (json.dumps({"slug": slug, "sections": {"Timeline": [{"date": "1983", "item": "Founded", "source": SRC}]}}),))
        # {"item": ...} is not a timeline field under the data rules: nothing is published, nothing is silently dropped
        assert c.execute("select count(*) from timeline_events where firm_id = %s", (fid,)).fetchone()[0] == 0
        assert c.execute("select count(*) from publish_checks where firm_id = %s and outcome in ('rejected', 'held')", (fid,)).fetchone()[0] >= 1
        c.rollback()


def test_every_publish_path_uses_the_checker():
    sql = (ROOT / "supabase" / "migrations" / "20261026050000_data_rules_checker.sql").read_text(encoding="utf-8")
    assert "create or replace function public.promote_bot_facts" in sql.lower() and "'submission', rec.sub" in sql
    assert "from checked_items(p_payload)" in sql and "people_note_guard" not in sql.split("--")[0]
    py = (ROOT / "tools" / "ingest" / "import_research.py").read_text(encoding="utf-8")
    assert "note_text(" in py and "person_name_bad(" in py
    assert (ROOT / "docs" / "DATA_RULES.md").exists()
    assert "DATA_RULES.md" in (ROOT / "docs" / "ENRICHER.md").read_text(encoding="utf-8")
