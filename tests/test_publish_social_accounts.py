"""Passed social accounts publish. Unapproved rows and other item types stay as they are."""
import os
import pathlib

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIG = (ROOT / "supabase/migrations/20261108211827_v2_publish_social_accounts.sql").read_text()
UNDO = (ROOT / "supabase/rollbacks/20261108211827_v2_publish_social_accounts.sql").read_text()
REPLAY = (ROOT / "supabase/replay/20261108211827_accel_approved_social.sql").read_text()
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()

BEFORE = r"""
CREATE OR REPLACE FUNCTION public.v2_publish_queue_item(p_qid bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE q v2_checker_queue; arch boolean; n int; pk text;
BEGIN
  SELECT * INTO q FROM v2_checker_queue WHERE queue_id = p_qid;
  IF NOT FOUND OR q.status <> 'passed' THEN RAISE EXCEPTION 'v2_publish: queue item % is not passed', p_qid; END IF;
  IF q.table_name = 'v2_firms' THEN RETURN 'Confirmed: firm field already applied at submit (empty field filled)'; END IF;
  IF q.table_name = 'v2_social_accounts' THEN RETURN 'Confirmed: saved, not shown yet (F11.8 social)'; END IF;
  pk := CASE q.table_name WHEN 'v2_investor_principles' THEN 'id' WHEN 'v2_firm_stages' THEN 'id' WHEN 'v2_firm_industries' THEN 'id' WHEN 'firm_fund_announcements' THEN 'id' WHEN 'v2_firm_check_sizes' THEN 'id' ELSE 'row_id' END;
  EXECUTE format('SELECT archived FROM public.%I WHERE %I = $1 AND submission_id = $2', q.table_name, pk) INTO arch USING q.row_id, q.submission_id;
  IF arch IS NULL THEN RAISE EXCEPTION 'v2_publish: row % in % not found', q.row_id, q.table_name; END IF;
  IF arch THEN RETURN 'Confirmed: kept archived and hidden (L4 / archived at entry, R2)'; END IF;
  IF q.table_name = 'v2_deals' THEN
    UPDATE v2_deals SET is_current = true, shown = (deal_date IS NOT NULL OR round_amount IS NOT NULL)
     WHERE row_id = q.row_id AND submission_id = q.submission_id;
    SELECT count(*) INTO n FROM v2_deals WHERE row_id = q.row_id AND shown;
    RETURN CASE WHEN n > 0 THEN 'Confirmed: published (deal shown, D1.8)' ELSE 'Confirmed: published, deal hidden (no date or amount, D1.8)' END;
  END IF;
  EXECUTE format('UPDATE public.%I SET is_current = true WHERE %I = $1 AND submission_id = $2', q.table_name, pk) USING q.row_id, q.submission_id;
  RETURN 'Confirmed: published';
END $function$;
"""


def _body(text):
    return "\n".join(line for line in text.splitlines() if not line.strip().startswith("--")).lower()


def test_migration_only_removes_the_social_early_return():
    low = _body(MIG)
    assert "to_regprocedure('public.v2_publish_queue_item(bigint)') is null" in low
    assert "raise notice 'v2 schema missing, skipped'" in low
    assert "f11.8 social" in low
    assert "v2_publish_queue_item(6573)" not in low
    assert "delete " not in low
    assert "drop table" not in low
    assert "truncate " not in low
    replay = _body(REPLAY)
    assert "v2_publish_queue_item(6573)" in replay
    assert "v2_publish_queue_item(6574)" in replay
    assert "v2_publish_queue_item(6575)" in replay
    assert "6576" not in replay
    assert replay.strip().endswith("rollback;")
    assert "commit;" not in replay
    undo = _body(UNDO)
    assert "f11.8 social" in undo
    assert "delete " not in undo


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
def test_passed_socials_publish_and_other_types_stay():
    import psycopg

    conn = psycopg.connect(DATABASE_URL)
    try:
        cur = conn.cursor()
        cur.execute(MIG)
        cur.execute(
            """
            create table public.v2_checker_queue (
              queue_id bigint primary key,
              submission_id bigint,
              firm_id bigint,
              table_name text,
              row_id bigint,
              status text,
              archived boolean not null default false
            );
            create table public.v2_social_accounts (
              row_id bigint,
              submission_id bigint,
              firm_id bigint,
              platform text,
              account_url text,
              follower_count bigint,
              source_url text,
              source_level smallint,
              is_current boolean not null default false,
              archived boolean not null default false,
              nothing_found boolean not null default false
            );
            create table public.v2_deals (
              row_id bigint,
              submission_id bigint,
              archived boolean not null default false,
              is_current boolean not null default false,
              shown boolean not null default false,
              deal_date date,
              round_amount numeric
            );
            create table public.v2_fund_assets (
              row_id bigint,
              submission_id bigint,
              archived boolean not null default false,
              is_current boolean not null default false
            );
            create table public.v2_firms (
              firm_id bigint primary key,
              is_current boolean not null default false
            );
            """
        )
        cur.execute(BEFORE)
        acl = cur.execute(
            "select prosecdef, proconfig::text, proacl::text from pg_proc where proname = 'v2_publish_queue_item'"
        ).fetchone()

        def publish(qid):
            cur.execute("select public.v2_publish_queue_item(%s)", (qid,))
            return cur.fetchone()[0]

        def refused(qid):
            cur.execute("savepoint refused")
            with pytest.raises(psycopg.errors.RaiseException, match="not passed"):
                publish(qid)
            cur.execute("rollback to savepoint refused")

        cur.execute(
            """
            insert into v2_checker_queue (queue_id, submission_id, firm_id, table_name, row_id, status) values
              (1, 101, 8, 'v2_social_accounts', 1, 'passed'),
              (2, 102, 99, 'v2_social_accounts', 2, 'passed'),
              (3, 103, 8, 'v2_social_accounts', 3, 'open'),
              (4, 104, 8, 'v2_social_accounts', 4, 'failed'),
              (5, 105, 8, 'v2_social_accounts', 5, 'passed'),
              (6, 106, 8, 'v2_deals', 6, 'passed'),
              (7, 107, 5, 'v2_fund_assets', 7, 'passed'),
              (8, 108, 8, 'v2_firms', 8, 'passed');
            insert into v2_social_accounts (row_id, submission_id, firm_id, is_current, archived) values
              (1, 101, 8, false, false),
              (2, 102, 99, false, false),
              (3, 103, 8, false, false),
              (4, 104, 8, false, false),
              (5, 105, 8, false, true);
            insert into v2_deals (row_id, submission_id, deal_date) values (6, 106, '2026-11-08');
            insert into v2_fund_assets (row_id, submission_id) values (7, 107);
            insert into v2_firms (firm_id) values (8);
            """
        )
        assert publish(1) == "Confirmed: saved, not shown yet (F11.8 social)"
        assert cur.execute("select is_current from v2_social_accounts where row_id = 1").fetchone()[0] is False

        cur.execute(MIG)
        assert "F11.8 social" not in cur.execute(
            "select pg_get_functiondef('public.v2_publish_queue_item(bigint)'::regprocedure)"
        ).fetchone()[0]
        assert cur.execute(
            "select prosecdef, proconfig::text, proacl::text from pg_proc where proname = 'v2_publish_queue_item'"
        ).fetchone() == acl
        assert cur.execute("select is_current from v2_social_accounts where row_id = 1").fetchone()[0] is False

        assert publish(1) == "Confirmed: published"
        assert publish(2) == "Confirmed: published"
        assert cur.execute(
            "select row_id from v2_social_accounts where is_current order by row_id"
        ).fetchall() == [(1,), (2,)]
        refused(3)
        refused(4)
        assert publish(5) == "Confirmed: kept archived and hidden (L4 / archived at entry, R2)"
        assert cur.execute(
            "select is_current from v2_social_accounts where row_id in (3, 4, 5) and is_current"
        ).fetchall() == []
        assert publish(6) == "Confirmed: published (deal shown, D1.8)"
        assert cur.execute("select is_current, shown from v2_deals where row_id = 6").fetchone() == (True, True)
        assert publish(7) == "Confirmed: published"
        assert cur.execute("select is_current from v2_fund_assets where row_id = 7").fetchone()[0] is True
        assert publish(8) == "Confirmed: firm field already applied at submit (empty field filled)"
        assert cur.execute("select is_current from v2_firms where firm_id = 8").fetchone()[0] is False

        cur.execute(UNDO)
        cur.execute(
            "insert into v2_checker_queue (queue_id, submission_id, firm_id, table_name, row_id, status) values (9, 109, 8, 'v2_social_accounts', 9, 'passed')"
        )
        cur.execute(
            "insert into v2_social_accounts (row_id, submission_id, firm_id) values (9, 109, 8)"
        )
        assert publish(9) == "Confirmed: saved, not shown yet (F11.8 social)"
        assert cur.execute("select is_current from v2_social_accounts where row_id = 9").fetchone()[0] is False
        cur.execute(MIG)
        assert publish(9) == "Confirmed: published"

        cur.execute("delete from v2_social_accounts")
        cur.execute("delete from v2_checker_queue")
        cur.execute(
            """
            insert into v2_checker_queue (queue_id, submission_id, firm_id, table_name, row_id, status) values
              (6573, 8286, 8, 'v2_social_accounts', 49, 'passed'),
              (6574, 8287, 8, 'v2_social_accounts', 50, 'passed'),
              (6575, 8288, 8, 'v2_social_accounts', 51, 'passed'),
              (7000, 9000, 5, 'v2_social_accounts', 90, 'passed'),
              (3, 103, 8, 'v2_social_accounts', 3, 'open');
            insert into v2_social_accounts
              (row_id, submission_id, firm_id, platform, account_url, follower_count, source_url, source_level) values
              (49, 8286, 8, 'X', 'https://x.com/accel', 340417, 'https://www.accel.com/', 2),
              (50, 8287, 8, 'LinkedIn', 'https://www.linkedin.com/company/accel-vc/', 347258, 'https://www.accel.com/', 2),
              (51, 8288, 8, 'YouTube', 'https://www.youtube.com/@AccelVC', 27000, 'https://www.accel.com/', 2),
              (90, 9000, 5, 'X', 'https://x.com/sequoia', 1, 'https://www.sequoiacap.com/', 2),
              (3, 103, 8, 'X', 'https://x.com/not-accel', 1, 'https://www.accel.com/', 2);
            """
        )
        start = REPLAY.index("do $replay$")
        end = REPLAY.index("-- Safe default.")
        cur.execute("savepoint replay_guard")
        with pytest.raises(psycopg.errors.RaiseException, match="exactly three"):
            cur.execute(REPLAY[start:end])
        cur.execute("rollback to savepoint replay_guard")
        cur.execute("delete from v2_social_accounts where row_id = 3")
        cur.execute("delete from v2_checker_queue where queue_id = 3")
        cur.execute(REPLAY[start:end])
        assert cur.execute(
            "select row_id from v2_social_accounts where is_current order by row_id"
        ).fetchall() == [(49,), (50,), (51,)]
        assert cur.execute("select is_current from v2_social_accounts where row_id = 90").fetchone()[0] is False
        assert cur.execute("select status from v2_checker_queue where queue_id = 7000").fetchone()[0] == "passed"
    finally:
        conn.rollback()
        conn.close()
