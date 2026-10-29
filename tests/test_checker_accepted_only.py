"""Step B: the Checker takes only entry-check Accepted rows and opens flagged links first (A5.4)."""
import json
import os
import uuid
from pathlib import Path

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
MIG = "supabase/migrations/20261029060000_checker_accepted_only.sql"
GOOD = "https://www.sec.gov/Archives/edgar/data/1/x.htm"
DEAD = "https://www.sec.gov/Archives/edgar/data/1/dead.htm"


def test_rule_written_down():
    guide = Path("docs/PAGE_DATA_GUIDE.md").read_text(encoding="utf-8")
    sql = Path(MIG).read_text(encoding="utf-8")
    assert "**A5.5**" in guide and "Rejected: link does not open" in guide
    assert "s.entry_check = 'Accepted'" in sql
    assert "'Rejected: link does not open'" in sql


@pytest.fixture()
def cur():
    if not DATABASE_URL:
        pytest.skip("DATABASE_URL is not set")
    import psycopg
    with psycopg.connect(DATABASE_URL) as c:
        if c.execute("select to_regprocedure('public._checker_entry_gate(bigint,jsonb)')").fetchone()[0] is None:
            pytest.skip("step B migration not applied")
        try:
            yield c
        finally:
            c.rollback()


def lab(cur):
    tag = uuid.uuid4().hex[:8]
    reg, slug = f"zz-stepb-{tag}", f"stepb-{tag}"
    cur.execute("insert into research_queue (registry_id, name, priority, status) values (%s, 'StepB Lab', 999999, 'submitted')", (reg,))
    cur.execute("insert into firms(slug, name, published, data_status, registry_id) values (%s, 'StepB Lab', true, 'real', %s)", (slug, reg))
    cur.execute("insert into ingest_settings(key, value) values ('lab_firm_slugs', %s) on conflict (key) do update set "
                "value = coalesce(ingest_settings.value, '') || ',' || excluded.value", (slug,))
    return reg


def submit(cur, reg, url, probes, door=None):
    p = {"firm": {"name": "StepB Lab", "primary_domain": "stepb.example"},
         "records": [{"field_path": "hq", "value": "Los Angeles", "as_of": "2025-12-31",
                      "sources": [{"url": url, "tier": "T1", "published_at": "2026-02-25"}]}],
         "probes": probes}
    return cur.execute("insert into bots.research_submissions(valid, registry_id, bot_id, payload, door_status) "
                       "values (true, %s, 'test-bot', %s::jsonb, %s) returning id, entry_check, entry_link_open_pending",
                       (reg, json.dumps(p), door)).fetchone()


def row(cur, i):
    return cur.execute("select entry_check, entry_link_open_pending, checked_at is not null, door_status "
                       "from bots.research_submissions where id = %s", (i,)).fetchone()


def test_gate_accepted_rejected_dead(cur):
    reg = lab(cur)
    ok = submit(cur, reg, GOOD, {GOOD: True}, door="waiting")
    assert ok[1:] == ("Accepted", True)
    assert cur.execute("select public._checker_entry_gate(%s)", (ok[0],)).fetchone()[0] is None
    assert row(cur, ok[0])[:2] == ("Accepted", False)
    bad = submit(cur, reg, None, {}, door="waiting")
    assert bad[1].startswith("Rejected:")
    g = cur.execute("select public._checker_entry_gate(%s)", (bad[0],)).fetchone()[0]
    assert g["reason"] == "entry check not Accepted"
    dead = submit(cur, reg, DEAD, {DEAD: False}, door="waiting")
    g = cur.execute("select public._checker_entry_gate(%s)", (dead[0],)).fetchone()[0]
    assert g["reason"] == "link does not open"
    assert row(cur, dead[0])[:2] == ("Rejected: link does not open", False)


def test_drain_takes_only_accepted(cur):
    cur.execute("insert into ingest_settings(key, value) values ('checker_publish', 'true') "
                "on conflict (key) do update set value = 'true'")
    reg = lab(cur)
    ok = submit(cur, reg, GOOD, {GOOD: True}, door="waiting")
    bad = submit(cur, reg, None, {}, door="waiting")
    dead = submit(cur, reg, DEAD, {DEAD: False}, door="waiting")
    cur.execute("update bots.research_submissions set door_status = 'ready', ready_at = now() where id = any(%s)",
                ([ok[0], bad[0], dead[0]],))
    cur.execute("select public.checker_drain(50)")
    assert row(cur, ok[0]) == ("Accepted", False, True, "checked")
    assert row(cur, bad[0])[2:] == (False, "ready")
    r = row(cur, dead[0])
    assert r[0] == "Rejected: link does not open" and r[3] == "checked"


def test_sections_shape_keeps_source_level(cur):
    p = {"sections": {"Press coverage": [{"outlet": "TechCrunch", "headline": "X raises", "url": "https://techcrunch.com/2026/10/28/x-zz",
                                          "date": "2026-10-28", "snippet": "X raised", "tier": "T3"}]}}
    assert cur.execute("select public._entry_check(null, 'zz-sec', 'test-bot', %s::jsonb)", (json.dumps(p),)).fetchone()[0] == "Accepted"
    del p["sections"]["Press coverage"][0]["tier"]
    assert "no source level" in cur.execute("select public._entry_check(null, 'zz-sec', 'test-bot', %s::jsonb)", (json.dumps(p),)).fetchone()[0]
