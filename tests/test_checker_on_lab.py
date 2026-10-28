"""Lab firms: enrich stays in holding, the Checker runs on each new submission, exact copies collapse."""
import json
import os
import uuid

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")


def _j(v):
    return v if isinstance(v, dict) else json.loads(v)


def test_migration_turns_the_checker_on_and_keeps_a_rollback():
    from pathlib import Path
    sql = Path("supabase/migrations/20261028100000_checker_on_lab.sql").read_text(encoding="utf-8")
    rollback = Path("supabase/rollbacks/20261028100000_checker_on_lab.sql").read_text(encoding="utf-8")
    assert "values ('checker_publish', 'true')" in sql
    assert "create trigger checker_on_submission" in sql
    assert "exact duplicate, kept one" in sql
    assert "old value kept as a note" in sql
    assert "value = 'false'" in rollback
    assert Path("supabase/rollbacks/20261028070000_checker_switch.sql").exists()


def test_lab_submission_publishes_once_and_a_different_value_is_a_note():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        assert cur.execute("select _checker_publish_on()").fetchone()[0] is True
        slug = "lab-on-" + uuid.uuid4().hex[:8]
        reg = "zz-on-" + uuid.uuid4().hex[:8]
        cur.execute("insert into research_queue (registry_id, name, priority, status) values (%s, 'Hold Lab', 5, 'submitted')", (reg,))
        fid = cur.execute(
            "insert into firms(slug, name, display_name, primary_domain, published, data_status, registry_id) "
            "values (%s, 'Hold Lab', 'Hold Lab', 'hold.example', true, 'real', %s) returning id",
            (slug, reg),
        ).fetchone()[0]
        cur.execute(
            "insert into ingest_settings(key, value) values ('lab_firm_slugs', %s) "
            "on conflict (key) do update set value = case when ingest_settings.value like %s then ingest_settings.value "
            "else ingest_settings.value || ',' || excluded.value end",
            (slug, "%" + slug + "%"),
        )
        assert cur.execute("select _lab_firm(%s)", (fid,)).fetchone()[0] is True
        cur.execute(
            "insert into firm_people_roles(id, firm_id, kind, person_name, role, sort_order) values "
            "(gen_random_uuid(), %s, 'officer', 'Ada Lovelace', 'Partner', 1),"
            "(gen_random_uuid(), %s, 'officer', 'Ada Lovelace', 'Partner', 2)",
            (fid, fid),
        )
        assert cur.execute("select count(*) from firm_people_roles where firm_id = %s", (fid,)).fetchone()[0] == 2
        removed = cur.execute("select _checker_keep_one_exact(%s)", (fid,)).fetchone()[0]
        assert removed >= 1
        assert cur.execute("select count(*) from firm_people_roles where firm_id = %s", (fid,)).fetchone()[0] == 1

        other = "zz-off-" + uuid.uuid4().hex[:8]
        cur.execute("insert into research_queue (registry_id, name, priority, status) values (%s, 'Not Lab', 5, 'submitted')", (other,))
        oid = cur.execute(
            "insert into firms(slug, name, published, data_status, registry_id) "
            "values (%s, 'Not Lab', true, 'real', %s) returning id",
            ("off-" + uuid.uuid4().hex[:8], other),
        ).fetchone()[0]
        story = {
            "sections": {"Press coverage": [{
                "outlet": "TechCrunch", "headline": "Not Lab raises a fund",
                "url": "https://techcrunch.com/2026/10/28/not-lab", "date": "2026-10-28", "snippet": "Not Lab raised",
            }]}
        }
        cur.execute(
            "insert into research_submissions(registry_id, bot_id, payload, record_count, valid) values (%s, 'toxy-enricher', %s::jsonb, 1, true)",
            (other, json.dumps(story)),
        )
        assert cur.execute("select count(*) from press_item_firms where firm_id = %s", (oid,)).fetchone()[0] == 0

        item = {
            "outlet": "TechCrunch", "headline": "Hold Lab raises a fund",
            "url": "https://techcrunch.com/2026/10/28/hold-lab", "date": "2026-10-28", "snippet": "Hold Lab raised",
        }
        payload = json.dumps({"sections": {"Press coverage": [item]}})
        cur.execute(
            "insert into research_submissions(registry_id, bot_id, payload, record_count, valid) values (%s, 'toxy-enricher', %s::jsonb, 1, true)",
            (reg, payload),
        )
        assert cur.execute(
            "select count(*) from press_item_firms pf join press_items p on p.id = pf.press_item_id "
            "where pf.firm_id = %s and p.url = %s",
            (fid, item["url"]),
        ).fetchone()[0] == 1
        cur.execute(
            "insert into research_submissions(registry_id, bot_id, payload, record_count, valid) values (%s, 'toxy-researcher-1', %s::jsonb, 1, true)",
            (reg, payload),
        )
        assert cur.execute(
            "select count(*) from press_item_firms pf join press_items p on p.id = pf.press_item_id "
            "where pf.firm_id = %s and p.url = %s",
            (fid, item["url"]),
        ).fetchone()[0] == 1
        longer = dict(item, headline="Hold Lab raises a much larger fund")
        cur.execute(
            "insert into research_submissions(registry_id, bot_id, payload, record_count, valid) values (%s, 'toxy-enricher', %s::jsonb, 1, true)",
            (reg, json.dumps({"sections": {"Press coverage": [longer]}})),
        )
        headline = cur.execute(
            "select p.headline from press_items p join press_item_firms pf on pf.press_item_id = p.id "
            "where pf.firm_id = %s and p.url = %s",
            (fid, item["url"]),
        ).fetchone()[0]
        assert headline == longer["headline"]
        assert cur.execute(
            "select count(*) from publish_checks where firm_id = %s and bot_id = 'checker' and outcome = 'note'",
            (fid,),
        ).fetchone()[0] >= 1
        conn.rollback()
