"""socialAccounts have their own Checker path: never firm_profile_facts (A2.10 / B3.8).
Re-runs the real 2026-10-29 payloads 5353 (a16z) and 5354 (YC), which failed on firm_profile_facts.label."""
import json
import os
import uuid
from pathlib import Path

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
MIG = "supabase/migrations/20261029190000_checker_social_path.sql"
FIX = json.loads(Path("tests/fixtures/social_5353_5354.json").read_text(encoding="utf-8"))


def test_migration_and_rollback_exist():
    sql = Path(MIG).read_text(encoding="utf-8")
    assert "when 'socialAccounts' then 'social'" in sql
    assert "'reasons', reasons" in sql
    assert Path("supabase/rollbacks/20261029190000_checker_social_path.sql").exists()


@pytest.fixture()
def cur():
    if not DATABASE_URL:
        pytest.skip("DATABASE_URL is not set")
    import psycopg
    with psycopg.connect(DATABASE_URL) as c:
        if c.execute("select to_regprocedure('public._checker_social(uuid,jsonb,text)')").fetchone()[0] is None:
            pytest.skip("social path migration not applied")
        c.execute("insert into ingest_settings(key, value) values ('checker_publish', 'true') "
                  "on conflict (key) do update set value = 'true'")
        try:
            yield c
        finally:
            c.rollback()


def lab(cur, name):
    tag = uuid.uuid4().hex[:8]
    reg, slug = f"zz-soc-{tag}", f"soc-{tag}"
    cur.execute("insert into research_queue (registry_id, name, priority, status) values (%s, %s, 999999, 'submitted')", (reg, f"{name} {tag}"))
    fid = cur.execute("insert into firms(slug, name, published, data_status, registry_id) values (%s, %s, true, 'real', %s) returning id",
                      (slug, f"{name} {tag}", reg)).fetchone()[0]
    cur.execute("insert into ingest_settings(key, value) values ('lab_firm_slugs', %s) on conflict (key) do update set "
                "value = coalesce(ingest_settings.value, '') || ',' || excluded.value", (slug,))
    return reg, fid


def run(cur, sub, reg=None):
    if reg is None:
        reg, fid = lab(cur, sub["payload"]["firm"]["name"])
    else:
        fid = None
    p = dict(sub["payload"]); p["probes"] = {sub["payload"]["firm"]["website"]: True}
    sid = cur.execute("insert into bots.research_submissions(valid, registry_id, bot_id, payload) values (true, %s, 'test-bot', %s::jsonb) "
                      "returning id", (reg, json.dumps(p))).fetchone()[0]
    # the insert trigger runs the Checker, as in production; fall back to a direct call if it did not
    rep = cur.execute("select checker_report from bots.research_submissions where id = %s", (sid,)).fetchone()[0]
    if rep is None:
        rep = cur.execute("select public.checker_publish_submission(%s)", (sid,)).fetchone()[0]
    return rep.get("firm_id") or fid, rep, reg


@pytest.mark.parametrize("sid,n", [(5353, 3), (5354, 1)])
def test_rerun_real_payloads_publish(cur, sid, n):
    sub = next(s for s in FIX if s["id"] == sid)
    fid, rep, reg = run(cur, sub)
    assert rep["ran"] is True, rep
    assert rep["failure"] == 0, rep["reasons"]
    social = [r for r in sub["payload"]["records"] if r["field_path"] == "socialAccounts"]
    plats = ("x", "linkedin") + (("substack",) if cur.execute(
        "select position('substack' in prosrc) > 0 from pg_proc where proname = '_checker_social'").fetchone()[0] else ())
    shown = [r for r in social if r["value"]["platform"] in plats]
    # published = the shown social accounts (+ the Website item, new in this empty test firm)
    assert rep["published"] >= len(shown), rep["reasons"]
    assert [x for x in rep["reasons"] if x["section"] == "social"] == [
        {"section": "social", "url": r["value"]["url"], "outcome": "skipped",
         "reason": f"skipped, platform {r['value']['platform']} is not shown on the page"} for r in social if r not in shown]
    assert cur.execute("select count(*) from firm_profile_facts where firm_id = %s and origin = 'checker' and label is null", (fid,)).fetchone()[0] == 0
    facts = cur.execute("select value, source_level, source_url from vc_source_facts where firm_id = %s and fact_type = 'media_reach'", (fid,)).fetchall()
    assert len(facts) == len(shown) and all(f[1] == 2 for f in facts)
    for v, _, url in facts:
        r = next(x["value"] for x in shown if x["value"]["url"] == url)
        assert v["linked_from"] == r["found_on_url"] and v["linked_checked"] == r["followers_read_at"]
        assert v["value"].startswith(str(r["followers"]))
    # every non-published item carries its reason into the report
    assert all(x["reason"] for x in rep["reasons"])
    # a re-run does not duplicate
    sid0 = cur.execute("select max(id) from bots.research_submissions where registry_id = %s", (reg,)).fetchone()[0]
    rep2 = cur.execute("select public.checker_publish_submission(%s)", (sid0,)).fetchone()[0]
    assert rep2["failure"] == 0 and rep2["published"] == 0, rep2
    assert all(x["reason"] in ("already on the page, not re-checked", "skipped, platform substack is not shown on the page")
               for x in rep2["reasons"] if x["section"] == "social")
    assert cur.execute("select count(*) from vc_source_facts where firm_id = %s and fact_type = 'media_reach'", (fid,)).fetchone()[0] == len(shown)


def test_not_linked_is_skipped_with_reason(cur):
    sub = json.loads(json.dumps(next(s for s in FIX if s["id"] == 5354)))
    sub["payload"]["records"][0]["value"]["linked_from_firm_site"] = False
    fid, rep, reg = run(cur, sub)
    assert rep["failure"] == 0
    assert any(x["reason"] == "skipped: not linked from the firm's site, not shown" for x in rep["reasons"])
    assert cur.execute("select count(*) from vc_source_facts where firm_id = %s", (fid,)).fetchone()[0] == 0
