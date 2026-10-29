"""Substack pill (Alex 2026-10-29): substack is allowed in _firm_social and the Checker social path."""
import os
import pathlib
import uuid

import pytest

from test_checker_social_path import FIX, run

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIG = ROOT / "supabase/migrations/20261029210000_social_substack.sql"
RB = ROOT / "supabase/rollbacks/20261029210000_social_substack.sql"
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()


def test_files():
    assert MIG.exists() and RB.exists()
    assert "'substack'" in MIG.read_text() and "'substack'" not in RB.read_text()
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


def test_a16z_payload_shows_substack(cur):
    sub = next(s for s in FIX if s["id"] == 5353)
    fid, rep, _ = run(cur, sub)
    assert rep["failure"] == 0 and not [x for x in rep["reasons"] if x["section"] == "social"], rep
    social = cur.execute("select public._firm_social(%s)", (fid,)).fetchone()[0]
    assert [a["platform"] for a in social] == ["linkedin", "x", "substack"]
    assert social[-1] == {"platform": "substack", "url": "https://a16z.substack.com", "followers": 280000}
    v = cur.execute("select value from vc_source_facts where firm_id = %s and value->>'field' = 'media_substack_followers'", (fid,)).fetchone()[0]
    assert v["linked_from"] == "https://www.a16z.com/" and v["publisher"] == "Substack"


def test_substack_url_must_be_substack(cur):
    fid = cur.execute("select id from firms order by slug limit 1").fetchone()[0]
    from psycopg.types.json import Jsonb
    for url, ok in [("https://evil.example/substack.com", False), ("https://a.substack.com/", True)]:
        cur.execute("delete from vc_source_facts where firm_id = %s and fact_type = 'media_reach'", (fid,))
        cur.execute("insert into vc_source_facts (firm_id, fact_type, section, value, source_url, source_level, status) values (%s, 'media_reach', 'social', %s, %s, 2, 'current')",
                    (fid, Jsonb({"field": "media_substack_followers", "value": "5000", "entity": "firm", "url": url}), url))
        got = [a for a in cur.execute("select public._firm_social(%s)", (fid,)).fetchone()[0] if a["platform"] == "substack"]
        assert bool(got) is ok, url
