"""Social pills (Alex 2026-10-29): firm_page().firm.social only from accounts linked on the firm's own site (level 2)."""
import os
import pathlib
import uuid

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIG = ROOT / "supabase/migrations/20261029120000_firm_social_pills.sql"
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()


def test_migration_text():
    s = MIG.read_text()
    assert s.count("'social', public._firm_social(f.id)") == 2
    assert "linked_from_firm_site" in s and "source_level = 2" in s
    assert "delete from public.firm_page_cache" in s
    assert (ROOT / "supabase/rollbacks/20261029120000_firm_social_pills.sql").exists()


@pytest.mark.skipif(not DATABASE_URL, reason="needs DATABASE_URL")
def test_only_level2_accounts():
    import psycopg
    from psycopg.types.json import Jsonb
    with psycopg.connect(DATABASE_URL) as c:
        fid = c.execute("select id from firms order by slug limit 1").fetchone()[0]
        assert c.execute("select public._firm_social(%s)", (fid,)).fetchone()[0] == []
        reg = "TEST-SOCIAL-" + uuid.uuid4().hex[:8]
        c.execute("insert into research_queue (registry_id, name, priority) values (%s, 'Social Test', 1)", (reg,))
        c.execute("update firms set registry_id = %s where id = %s", (reg, fid))
        recs = [
            {"field_path": "socialAccounts", "value": {"platform": "linkedin", "url": "https://www.linkedin.com/company/t", "followers": 412345, "linked_from_firm_site": True}},
            {"field_path": "socialAccounts", "value": {"platform": "instagram", "url": "https://instagram.com/t", "followers": 9, "linked_from_firm_site": False}},
            {"field_path": "socialAccounts", "value": {"platform": "youtube", "url": "https://evil.example/t", "followers": 9, "linked_from_firm_site": True}},
        ]
        c.execute("insert into bots.research_submissions (registry_id, bot_id, payload, valid) values (%s, 'test', %s, true)", (reg, Jsonb({"records": recs})))
        def media(val, lvl, url):
            c.execute("insert into vc_source_facts (firm_id, fact_type, section, value, source_url, source_level, status) values (%s, 'media_reach', 'social', %s, %s, %s, 'current')",
                      (fid, Jsonb(val), url, lvl))
        media({"field": "media_x_followers", "value": "133093 (@t)", "entity": "firm"}, 2, "https://x.com/t")
        media({"field": "media_youtube_followers", "value": "500", "entity": "firm"}, None, "https://youtube.com/@t")
        media({"field": "media_tiktok_followers", "value": "7", "entity": "partner:someone"}, 2, "https://tiktok.com/@p")
        out = c.execute("select public._firm_social(%s)", (fid,)).fetchone()[0]
        page = c.execute("select public.firm_page((select slug from firms where id = %s), gen_random_uuid(), false, null)->'firm'->'social'", (fid,)).fetchone()[0]
        c.rollback()
    got = [(a["platform"], a["url"], int(a["followers"])) for a in out]
    assert got == [("linkedin", "https://www.linkedin.com/company/t", 412345), ("x", "https://x.com/t", 133093)]
    assert page == out
