"""A finder can submit without a claim. The row stays in holding. The switch stays off."""
import json
import os
import uuid

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")


def _j(v):
    return v if isinstance(v, dict) else json.loads(v)


def test_migration_keeps_the_switch_off_and_holds_unclaimed_submits():
    from pathlib import Path
    sql = Path("supabase/migrations/20261028090000_finder_holding_submit.sql").read_text(encoding="utf-8")
    assert "values ('checker_publish', 'false')" in sql
    assert "'status', 'holding'" in sql
    assert "perform promote_enrichment(new.firm_id)" in sql
    assert "checker_publish_firm" not in sql


def test_unclaimed_submit_stays_in_holding_and_switch_on_does_not_publish():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        assert cur.execute("select _checker_publish_on()").fetchone()[0] is True
        reg = "zz-hold-" + uuid.uuid4().hex[:8]
        cur.execute(
            "insert into research_queue (registry_id, name, priority, status, claimed_by) "
            "values (%s, 'Zz Already Submitted', 5, 'submitted', 'toxy-researcher-1')",
            (reg,),
        )
        domain_before = cur.execute("select count(*) from firms where primary_domain = 'finder-holding.example'").fetchone()[0]
        got = _j(cur.execute(
            "select research_submit(%s, 'toxy-enricher', %s::jsonb, 1, true, '[]'::jsonb)",
            (reg, json.dumps({"records": [{"field_path": "founded", "value": "2012"}]})),
        ).fetchone()[0])
        assert got["ok"] is True and got["status"] == "holding" and got["held_for_checker"] is True
        assert cur.execute(
            "select status, claimed_by from research_queue where registry_id = %s", (reg,)
        ).fetchone() == ("submitted", "toxy-researcher-1")
        assert cur.execute(
            "select count(*) from research_submissions where id = %s and bot_id = 'toxy-enricher'",
            (got["submission_id"],),
        ).fetchone()[0] == 1
        assert cur.execute("select count(*) from firms where primary_domain = 'finder-holding.example'").fetchone()[0] == domain_before

        slug = "lab-hold-" + uuid.uuid4().hex[:8]
        fid = cur.execute(
            "insert into firms(slug, name, primary_domain, published, data_status) "
            "values (%s, 'Hold Lab', 'hold.example', true, 'real') returning id",
            (slug,),
        ).fetchone()[0]
        cur.execute(
            "insert into ingest_settings(key, value) values ('lab_firm_slugs', %s) "
            "on conflict (key) do update set value = excluded.value",
            (slug,),
        )
        cur.execute(
            "insert into ingest_settings(key, value) values ('checker_publish', 'true') "
            "on conflict (key) do update set value = 'true'"
        )
        assert cur.execute("select _checker_publish_on()").fetchone()[0] is True
        assert cur.execute("select _lab_firm(%s)", (fid,)).fetchone()[0] is True
        facts_before = cur.execute("select count(*) from firm_profile_facts where firm_id = %s", (fid,)).fetchone()[0]
        press_before = cur.execute("select count(*) from press_item_firms where firm_id = %s", (fid,)).fetchone()[0]
        ereg = "zz-enrich-" + uuid.uuid4().hex[:8]
        cur.execute(
            "insert into research_queue (registry_id, name, priority, status) values (%s, 'Hold Lab', 5, 'submitted')",
            (ereg,),
        )
        cur.execute("update firms set registry_id = %s where id = %s", (ereg, fid))
        cur.execute(
            "insert into research_enrichments(bot_id, registry_id, firm_id, payload, valid, accepted) "
            "values ('toxy-enricher', %s, %s, %s::jsonb, true, 1)",
            (ereg, fid, json.dumps({"slug": slug, "sections": {"Overview": [{"label": "Website", "value": "https://new.example"}]}})),
        )
        assert cur.execute(
            "select count(*) from research_submissions where registry_id = %s and bot_id = 'toxy-enricher'",
            (ereg,),
        ).fetchone()[0] == 1
        assert cur.execute("select primary_domain from firms where id = %s", (fid,)).fetchone()[0] == "hold.example"
        assert cur.execute("select count(*) from firm_profile_facts where firm_id = %s", (fid,)).fetchone()[0] == facts_before
        assert cur.execute("select count(*) from press_item_firms where firm_id = %s", (fid,)).fetchone()[0] == press_before
        conn.rollback()
