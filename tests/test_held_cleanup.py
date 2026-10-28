"""Held lab rows: a real source moves home, a weak source is deleted and cannot come back."""
import os
import uuid

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")


def test_cleanup_moves_a_register_source_and_blocks_a_failed_one():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        slug = "held-" + uuid.uuid4().hex[:8]
        reg = "zz-held-" + uuid.uuid4().hex[:8]
        cur.execute("insert into research_queue (registry_id, name, priority, status) values (%s, 'Held Lab', 5, 'submitted')", (reg,))
        fid = cur.execute(
            "insert into firms(slug, name, primary_domain, published, data_status, registry_id) "
            "values (%s, 'Held Lab', 'held.example', true, 'real', %s) returning id",
            (slug, reg),
        ).fetchone()[0]
        cur.execute(
            "insert into ingest_settings(key, value) values ('lab_firm_slugs', %s) "
            "on conflict (key) do update set value = case when ingest_settings.value like %s then ingest_settings.value "
            "else coalesce(ingest_settings.value, '') || ',' || excluded.value end",
            (slug, "%" + slug + "%"),
        )
        good = "https://adviserinfo.sec.gov/firm/summary/" + uuid.uuid4().hex[:6]
        bad = "https://example.com/blog/" + uuid.uuid4().hex[:6]
        gid = cur.execute(
            "insert into firm_profile_facts(firm_id, section, label, value, sort_order) "
            "values (%s, 'funds', 'HELD GROWTH FUND L.P.', 'Venture', 1) returning id",
            (fid,),
        ).fetchone()[0]
        bid = cur.execute(
            "insert into firm_profile_facts(firm_id, section, label, value, sort_order) "
            "values (%s, 'funds', 'Random blog note', 'Not a filing', 2) returning id",
            (fid,),
        ).fetchone()[0]
        for fact, url in ((gid, good), (bid, bad)):
            sid = cur.execute("insert into sources(url, domain) values (%s, 'example') returning id", (url,)).fetchone()[0]
            cur.execute(
                "insert into fact_sources(source_id, firm_id, fact_type, fact_id, sort_order) "
                "values (%s, %s, 'firm_profile_facts', %s, 0)",
                (sid, fid, fact),
            )
        pid = cur.execute("insert into people(full_name) values ('Ada Held') returning id").fetchone()[0]
        fpid = cur.execute(
            "insert into fund_people(person_id, firm_id, role) values (%s, %s, 'Partner') returning id",
            (pid, fid),
        ).fetchone()[0]
        for key, kind in ((f"held:{gid}", "funds"), (f"held:{bid}", "funds"), (f"held:{fpid}", "people")):
            cur.execute(
                "insert into home_merge_log(firm_id, kind, item_key, action, detail) values (%s, %s, %s, 'held', '{}')",
                (fid, kind, key),
            )
        dry = cur.execute(
            "select kind, passed, failed from lab_held_cleanup(false) where slug = %s order by kind",
            (slug,),
        ).fetchall()
        assert ("funds", 1, 1) in dry
        assert ("people", 0, 1) in dry
        assert cur.execute("select count(*) from firm_profile_facts where firm_id = %s", (fid,)).fetchone()[0] == 2
        wrote = cur.execute(
            "select kind, passed, failed from lab_held_cleanup(true) where slug = %s order by kind",
            (slug,),
        ).fetchall()
        assert ("funds", 1, 1) in wrote
        assert cur.execute("select count(*) from funds where firm_id = %s and name = 'HELD GROWTH FUND L.P.'", (fid,)).fetchone()[0] == 1
        assert cur.execute("select count(*) from firm_profile_facts where firm_id = %s", (fid,)).fetchone()[0] == 0
        assert cur.execute("select count(*) from fund_people where id = %s", (fpid,)).fetchone()[0] == 0
        assert cur.execute("select count(*) from people where id = %s", (pid,)).fetchone()[0] == 1
        assert cur.execute("select count(*) from home_held_backup where firm_id = %s", (fid,)).fetchone()[0] == 3
        blocked = cur.execute(
            "select outcome, reason from _checker_decide(%s, 'funds', '{\"label\":\"Random blog note\"}'::jsonb, %s, null, null)",
            (fid, bad),
        ).fetchone()
        assert blocked[0] == "failure" and "rejected earlier" in blocked[1]
        mid = cur.execute(
            "insert into legal_matters(title) values ('ZZ Matter Held') returning id"
        ).fetchone()[0]
        cur.execute(
            "insert into legal_matter_firms(matter_id, firm_id) values (%s, %s)",
            (mid, fid),
        )
        cur.execute(
            "insert into home_merge_log(firm_id, kind, item_key, action, detail) values (%s, 'legal', %s, 'held', '{}')",
            (fid, "held:matter:" + str(mid)),
        )
        matter = cur.execute(
            "select kind, passed, failed from lab_held_cleanup(true) where slug = %s and kind = 'legal'",
            (slug,),
        ).fetchone()
        assert matter == ("legal", 0, 1)
        assert cur.execute(
            "select count(*) from legal_matter_firms where firm_id = %s and matter_id = %s",
            (fid, mid),
        ).fetchone()[0] == 0
        assert cur.execute(
            "select count(*) from home_held_backup where firm_id = %s and table_name = 'legal_matter_firms'",
            (fid,),
        ).fetchone()[0] == 1
        conn.rollback()
