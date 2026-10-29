"""_firm_social shows only Checker-approved social accounts and never reads raw socialAccounts uploads."""
import json
import os
import pathlib

import pytest

from test_checker_social_path import FIX, lab, run

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIG = ROOT / "supabase/migrations/20261029220000_firm_social_checker_only.sql"
RB = ROOT / "supabase/rollbacks/20261029220000_firm_social_checker_only.sql"
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()


def body(sql):
    return sql.split("AS $function$", 1)[1].split("$function$", 1)[0]


def test_files():
    assert MIG.exists() and RB.exists()
    assert "research_submissions" not in body(MIG.read_text()) and "socialAccounts" not in body(MIG.read_text())
    assert "research_submissions" in body(RB.read_text())
    assert "delete from public.firm_page_cache" in MIG.read_text()


@pytest.fixture
def cur():
    if not DATABASE_URL:
        pytest.skip("needs DATABASE_URL")
    import psycopg
    c = psycopg.connect(DATABASE_URL)
    with c:
        c.execute("insert into ingest_settings(key, value) values ('checker_publish', 'true') on conflict (key) do update set value = 'true'")
        try:
            yield c
        finally:
            c.rollback()


def test_raw_upload_alone_shows_nothing(cur):
    sub = next(s for s in FIX if s["id"] == 5353)
    reg, fid = lab(cur, "Raw only")
    cur.execute("insert into ingest_settings(key, value) values ('checker_publish', 'false') on conflict (key) do update set value = 'false'")
    cur.execute("insert into bots.research_submissions(valid, registry_id, bot_id, payload) values (true, %s, 'test-bot', %s::jsonb)",
                (reg, json.dumps(sub["payload"])))
    assert cur.execute("select public._firm_social(%s)", (fid,)).fetchone()[0] == []


def test_checker_approved_shows(cur):
    sub = next(s for s in FIX if s["id"] == 5354)
    fid, rep, _ = run(cur, sub)
    assert rep["failure"] == 0, rep
    social = cur.execute("select public._firm_social(%s)", (fid,)).fetchone()[0]
    assert social == [{"platform": "x", "url": "https://twitter.com/ycombinator", "followers": 1662038}]


def test_rejected_item_never_shows(cur):
    sub = json.loads(json.dumps(next(s for s in FIX if s["id"] == 5354)))
    sub["payload"]["records"][0]["value"]["followers"] = "lots"  # Checker: followers must be a number
    fid, rep, _ = run(cur, sub)
    assert any(x["reason"] == "social followers must be a number" for x in rep["reasons"]), rep
    assert cur.execute("select public._firm_social(%s)", (fid,)).fetchone()[0] == []
