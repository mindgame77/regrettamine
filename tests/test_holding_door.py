"""Holding door: known keys, hourly firm cap, exact copies, oldest-first queue."""
import json
import os
import uuid

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")


def _j(v):
    return v if isinstance(v, dict) else json.loads(v)


def test_door_rules_are_written_down():
    from pathlib import Path
    guide = Path("docs/PAGE_DATA_GUIDE.md").read_text(encoding="utf-8")
    sql = Path("supabase/migrations/20261028120000_holding_door.sql").read_text(encoding="utf-8")
    one = Path("supabase/migrations/20261028130000_hour_cap_and_marks.sql").read_text(encoding="utf-8")
    assert "The holding door" in guide
    assert "starts at 100" in guide
    assert "three times the limit" in guide
    assert "There is no second setting" in guide
    assert "7 days" in guide and "30 days" in guide
    assert "('door_hour_cap', '100')" in sql
    assert "attack := cap * 3" in one
    assert "door_attack_at" not in one.split("delete from bots.ingest_settings where key = 'door_attack_at';", 1)[-1]
    assert "interval '7 days'" in Path("supabase/migrations/20261028070000_checker_switch.sql").read_text(encoding="utf-8")
    assert "interval '30 days'" in Path("supabase/migrations/20261027010000_bots_schema.sql").read_text(encoding="utf-8")


def test_cap_wait_attack_duplicate_and_oldest_first():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        bot = "door-" + uuid.uuid4().hex[:8]
        cur.execute("insert into ingest_keys(name, key_hash, active, bot_id) values (%s, %s, true, %s)",
                    (bot, "hash-" + bot, bot))
        cur.execute("insert into ingest_settings(key, value) values ('door_hour_cap', '1') on conflict (key) do update set value = '1'")
        cur.execute("delete from ingest_settings where key = 'door_attack_at'")
        cur.execute("insert into ingest_settings(key, value) values ('door_attack_at', '99')")
        ids = []
        for i, name in enumerate(("Alpha Door", "Beta Door", "Gamma Door")):
            reg = f"zz-door-{bot}-{i}"
            cur.execute("insert into research_queue (registry_id, name, priority, status) values (%s, %s, 5, 'submitted')", (reg, name))
            slug = f"door-{bot}-{i}"
            cur.execute(
                "insert into firms(slug, name, published, data_status, registry_id) values (%s, %s, true, 'real', %s)",
                (slug, name, reg),
            )
            if i == 0:
                cur.execute(
                    "insert into ingest_settings(key, value) values ('lab_firm_slugs', %s) "
                    "on conflict (key) do update set value = case when ingest_settings.value like %s then ingest_settings.value "
                    "else coalesce(ingest_settings.value, '') || ',' || excluded.value end",
                    (slug, "%" + slug + "%"),
                )
            payload = json.dumps({"firm": {"name": name, "website_source_url": f"https://{slug}.example/"}, "records": []})
            got = _j(cur.execute(
                "select research_submit(%s, %s, %s::jsonb, 0, true, '[]'::jsonb)",
                (reg, bot, payload),
            ).fetchone()[0])
            ids.append((reg, got))
        assert ids[0][1]["status"] == "holding"
        assert ids[1][1]["status"] == "waiting"
        assert ids[2][1]["status"] == "waiting"
        again = _j(cur.execute(
            "select research_submit(%s, %s, %s::jsonb, 0, true, '[]'::jsonb)",
            (ids[0][0], bot, json.dumps({"firm": {"name": "Alpha Door", "website_source_url": "https://door-x.example/"}, "records": []})),
        ).fetchone()[0])
        # same registry and a different body is not an exact copy; the firm is already in the hour, so it is ready
        assert again["status"] == "holding"
        copy = _j(cur.execute(
            "select research_submit(%s, %s, %s::jsonb, 0, true, '[]'::jsonb)",
            (ids[0][0], bot, json.dumps({"firm": {"name": "Alpha Door", "website_source_url": f"https://door-{bot}-0.example/"}, "records": []})),
        ).fetchone()[0])
        assert copy["status"] == "duplicate" and copy["dropped"] is True
        reg4 = f"zz-door-{bot}-3"
        cur.execute("insert into research_queue (registry_id, name, priority, status) values (%s, 'Delta Door', 5, 'submitted')", (reg4,))
        blocked = _j(cur.execute(
            "select research_submit(%s, %s, %s::jsonb, 0, true, '[]'::jsonb)",
            (reg4, bot, json.dumps({"firm": {"name": "Delta"}, "records": []})),
        ).fetchone()[0])
        assert blocked["error"] == "blocked"
        assert cur.execute("select active from ingest_keys where name = %s", (bot,)).fetchone()[0] is False
        assert cur.execute(
            "select count(*) from research_submissions where bot_id = %s and door_status = 'frozen'", (bot,)
        ).fetchone()[0] == 2
        assert cur.execute("select count(*) from door_alerts where bot_id = %s and kind = 'attack'", (bot,)).fetchone()[0] == 1
        other = "door-b-" + uuid.uuid4().hex[:6]
        cur.execute("insert into ingest_keys(name, key_hash, active, bot_id) values (%s, %s, true, %s)", (other, "hash-" + other, other))
        assert cur.execute("select active from ingest_keys where name = %s", (other,)).fetchone()[0] is True
        opened = _j(cur.execute("select door_unblock(%s)", (bot,)).fetchone()[0])
        assert opened["ok"] is True
        assert cur.execute("select active from ingest_keys where name = %s", (bot,)).fetchone()[0] is True
        assert cur.execute("select count(*) from door_alerts where bot_id = %s", (bot,)).fetchone()[0] == 0
        unknown = _j(cur.execute(
            "select research_submit(%s, 'not-a-known-bot', '{}'::jsonb, 0, true, '[]'::jsonb)",
            (ids[0][0],),
        ).fetchone()[0])
        assert unknown["error"] == "unknown bot"

        # oldest ready row is checked first
        cur.execute("update research_submissions set door_status = 'ready', checked_at = null, received_at = now() - interval '2 hour' where bot_id = %s and registry_id = %s", (bot, ids[0][0]))
        cur.execute("update research_submissions set door_status = 'ready', checked_at = null, received_at = now() - interval '1 hour' where bot_id = %s and registry_id = %s", (bot, ids[1][0]))
        cur.execute("update research_submissions set door_status = 'waiting', checked_at = null, ready_at = now() + interval '1 hour' where bot_id = %s and registry_id = %s", (bot, ids[2][0]))
        n = cur.execute("select checker_drain(1)").fetchone()[0]
        assert n == 1
        first = cur.execute(
            "select registry_id, checked_at is not null from research_submissions where bot_id = %s and door_status = 'checked' order by received_at limit 1",
            (bot,),
        ).fetchone()
        assert first[0] == ids[0][0] and first[1] is True
        assert cur.execute(
            "select checked_at is null from research_submissions where bot_id = %s and registry_id = %s",
            (bot, ids[2][0]),
        ).fetchone()[0] is True

        for i in range(10):
            reg = f"zz-fail-{bot}-{i}"
            cur.execute("insert into research_queue (registry_id, name, priority, status) values (%s, 'Fail', 5, 'queued')", (reg,))
            outcome = "failure" if i < 6 else "published"
            report = json.dumps({"failure": 1 if outcome == "failure" else 0, "published": 0 if outcome == "failure" else 1,
                                  "merged": 0, "skipped": 0, "unconfirmed": 0, "note": 0})
            cur.execute(
                "insert into research_submissions(registry_id, bot_id, payload, record_count, valid, door_status, checked_at, checker_report) "
                "values (%s, %s, '{}'::jsonb, 0, true, 'checked', now(), %s::jsonb)",
                (reg, bot, report),
            )
        cur.execute("select _door_fail_rate(%s)", (bot,))
        assert cur.execute("select active from ingest_keys where name = %s", (bot,)).fetchone()[0] is False
        assert cur.execute("select count(*) from door_alerts where bot_id = %s and kind = 'fail_rate'", (bot,)).fetchone()[0] == 1
        conn.rollback()
