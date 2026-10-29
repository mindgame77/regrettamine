"""Fix 2: our own write / DB-constraint errors never count toward a bot's fail rate (only real data rejections do)."""
import json
import os
import pathlib
import uuid

import psycopg
import pytest

from test_checker_social_path import FIX, run

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIG = ROOT / "supabase/migrations/20261029200000_door_ignore_internal_errors.sql"
RB = ROOT / "supabase/rollbacks/20261029200000_door_ignore_internal_errors.sql"
DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/regrettamine")


@pytest.fixture
def cur():
    try:
        c = psycopg.connect(DATABASE_URL)
    except Exception:
        pytest.skip("no database")
    with c:
        if not c.execute("select to_regproc('public._checker_internal_error') is not null").fetchone()[0]:
            pytest.skip("migration not applied")
        c.execute("insert into ingest_settings(key, value) values ('checker_publish', 'true') "
                  "on conflict (key) do update set value = 'true'")
        try:
            yield c
        finally:
            c.rollback()


def test_files_exist():
    assert MIG.exists() and RB.exists()
    assert "_door_fail_rate" in RB.read_text() and "drop function if exists public._checker_internal_error" in RB.read_text()


@pytest.mark.parametrize("reason,internal", [
    ('write failed: null value in column "label" of relation "firm_profile_facts" violates not-null constraint', True),
    ('duplicate key value violates unique constraint "x_pkey"', True),
    ('insert or update on table "a" violates foreign key constraint "b"', True),
    ("link did not open", False),
    ("link does not match the firm", False),
    ("social followers must be a number", False),
    (None, False),
])
def test_classify(cur, reason, internal):
    assert cur.execute("select public._checker_internal_error(%s)", (reason,)).fetchone()[0] is internal


def _bot(cur):
    bot = f"zz-door-{uuid.uuid4().hex[:8]}"
    cur.execute("insert into bots.ingest_keys(name, key_hash, active, rate_limit_per_min, bot_id) values (%s, md5(random()::text), true, 60, %s)",
                (bot, bot))
    cur.execute("insert into ingest_settings(key, value) values ('door_fail_min', '10') on conflict (key) do update set value = '10'")
    return bot


def _report(cur, bot, rep, holding_reasons):
    reg = f"zz-{uuid.uuid4().hex[:8]}"
    cur.execute("insert into research_queue (registry_id, name, priority, status) values (%s, %s, 999999, 'submitted')", (reg, reg))
    sid = cur.execute("insert into bots.research_submissions(valid, registry_id, bot_id, payload) values (false, %s, %s, '{}'::jsonb) returning id",
                      (reg, bot)).fetchone()[0]
    cur.execute("update bots.research_submissions set checked_at = now(), checker_report = %s::jsonb where id = %s", (json.dumps(rep), sid))
    for r in holding_reasons:
        cur.execute("insert into bots.checker_holding(origin, origin_id, kind, outcome, reason) values ('submission', %s, 'overview', 'failure', %s)",
                    (sid, r))


def _active(cur, bot):
    return cur.execute("select active from bots.ingest_keys where name = %s", (bot,)).fetchone()[0]


def test_legacy_write_failures_do_not_pause(cur):
    # the toxy-enricher case: 7 of 10 'failures' were our own write errors on social accounts
    bot = _bot(cur)
    _report(cur, bot, {"ran": True, "published": 2, "skipped": 1, "failure": 7},
            ['write failed: null value in column "label" of relation "firm_profile_facts" violates not-null constraint'] * 7)
    cur.execute("select public._door_fail_rate(%s)", (bot,))
    assert _active(cur, bot) is True
    assert cur.execute("select count(*) from bots.door_alerts where bot_id = %s", (bot,)).fetchone()[0] == 0


def test_new_internal_count_ignored(cur):
    bot = _bot(cur)
    _report(cur, bot, {"ran": True, "published": 3, "failure": 0, "internal": 9}, [])
    _report(cur, bot, {"ran": True, "published": 7, "failure": 0, "internal": 0}, [])
    cur.execute("select public._door_fail_rate(%s)", (bot,))
    assert _active(cur, bot) is True


def test_real_data_rejections_still_pause(cur):
    bot = _bot(cur)
    _report(cur, bot, {"ran": True, "published": 3, "failure": 7}, ["link did not open"] * 7)
    cur.execute("select public._door_fail_rate(%s)", (bot,))
    assert _active(cur, bot) is False
    assert cur.execute("select count(*) from bots.door_alerts where bot_id = %s and kind = 'fail_rate'", (bot,)).fetchone()[0] == 1


def test_mixed_legacy_counts_only_data_failures(cur):
    bot = _bot(cur)
    # 6 data failures + 4 write errors out of 14 items: 6 of 10 real verdicts failed -> pause
    _report(cur, bot, {"ran": True, "published": 4, "failure": 10}, ["link did not open"] * 6 + ["write failed: x violates check constraint y"] * 4)
    cur.execute("select public._door_fail_rate(%s)", (bot,))
    assert _active(cur, bot) is False


def test_publish_reports_write_error_as_internal(cur):
    # make our own write fail with a DB constraint error and check the Checker reports it as internal, not failure
    cur.execute("""create function pg_temp.boom() returns trigger language plpgsql as $$
                   begin raise not_null_violation using message = 'null value in column "value" of relation "vc_source_facts" violates not-null constraint'; end $$""")
    cur.execute("create trigger zz_boom before insert on public.vc_source_facts for each row execute function pg_temp.boom()")
    sub = next(s for s in FIX if s["id"] == 5354)
    fid, rep, _ = run(cur, sub)
    assert rep["ran"] is True and rep["failure"] == 0, rep
    assert rep["internal"] >= 1, rep
    assert any(x["outcome"] == "internal" and "violates not-null constraint" in x["reason"] for x in rep["reasons"])
