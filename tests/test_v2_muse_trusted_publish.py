"""Muse trusted publication is one removable path on the existing submit function.

Authenticated external-muse-bot key 322 publishes a structurally valid item through
v2_publish_queue_item. A flagged item stays held. Other bots stay on the Checker.
A payload flag cannot choose the path. The rollback returns later Muse submissions
to the Checker and leaves published rows in place.
"""
import json
import os
import pathlib

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIG = (ROOT / "supabase/migrations/20261109030000_v2_muse_trusted_publish.sql").read_text()
UNDO = (ROOT / "supabase/rollbacks/20261109030000_v2_muse_trusted_publish.sql").read_text()
GUIDE = (ROOT / "docs/PAGE_DATA_GUIDE.md").read_text()
SUBMIT_SRC = (ROOT / "supabase/migrations/20261104205556_v2_reviews_name_source.sql").read_text()
DOORS_SRC = (ROOT / "supabase/migrations/20261107220000_v2_doors_checker_first.sql").read_text()
DOOR = (ROOT / "supabase/functions/research-ingest-v2/index.ts").read_text()
DSN = os.environ.get("MUSE_TEST_DSN") or os.environ.get("DATABASE_URL") or "dbname=ubuntu"

MUSE = "00000000-0000-0000-0000-000000000322"
CONDUCTOR = "00000000-0000-0000-0000-000000000001"
PORTAL = "00000000-0000-0000-0000-000000000002"

PUBLISH = r"""
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

BEFORE_TEMPLATE = r"""
CREATE OR REPLACE FUNCTION public.v2_research_submit(p_key_id uuid, p_items jsonb, p_dry_run boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'bots'
AS $function$
DECLARE
  ik bots.ingest_keys; bk public.v2_bot_keys; bot text; batch bigint;
  it jsonb; idx int := -1; reason text; sid bigint; fid bigint; res jsonb;
  sec_id smallint; o_site text; __DECL_OLD__
  tbl text; box text; fact jsonb; p jsonb; newid bigint; q_kind text; cols text;
  acc int := 0; rejn int := 0; held int := 0; results jsonb := '[]'::jsonb;
  src_keys text[] := ARRAY['source_url','source_level','source_date','source_date_precision','source_date_is_found_date','source_type','source_owner','archived_url','nothing_found'];
BEGIN
  SELECT * INTO ik FROM bots.ingest_keys WHERE id = p_key_id AND active;
  IF NOT FOUND OR ik.bot_id IS NULL THEN RETURN jsonb_build_object('ok',false,'error','this key is not linked to a bot'); END IF;
  bot := ik.bot_id;
__KEY_OLD__
  IF bk.frozen THEN
    RETURN jsonb_build_object('ok',false,'error',format('Key frozen: %s, %s', coalesce(bk.freeze_reason,'no reason'), to_char(bk.freeze_date AT TIME ZONE 'America/Los_Angeles','YYYY-MM-DD HH24:MI "PT"')));
  END IF;
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN RETURN jsonb_build_object('ok',false,'error','items must be a non-empty array'); END IF;
  batch := nextval('public.v2_batch_seq');
  BEGIN
  FOR it IN SELECT value FROM jsonb_array_elements(p_items) LOOP
__LOOP_OLD__
    IF jsonb_typeof(it) <> 'object' THEN
      results := results || jsonb_build_object('index',idx,'status','Rejected: item must be an object'); CONTINUE; END IF;
    tbl := it->>'table'; box := it->>'box'; fact := coalesce(it->'fact','{}'::jsonb);
    fid := CASE WHEN (it->>'firm_id') ~ '^\d+$' THEN (it->>'firm_id')::bigint END;
    IF box IS NULL OR box !~ '^[A-Z]{1,3}[0-9]{1,3}[a-z]?$' THEN reason := 'box required (e.g. F12)';
    ELSIF tbl IS NULL OR tbl NOT IN ('v2_deals','v2_firms') THEN reason := format('unknown table "%s" (P9)', coalesce(tbl,''));
    ELSE
      fact := fact || jsonb_build_object('source_owner', bot);
      IF coalesce(fact->>'source_url','') = '' THEN reason := 'no source link (source_url)';
      ELSIF coalesce(fact->>'source_level','') !~ '^[1-4]$' THEN reason := 'no source level (source_level must be 1, 2, 3 or 4)';
      ELSIF coalesce(fact->>'source_date','') !~ '^\d{4}-\d{2}-\d{2}$' THEN reason := 'no source date (source_date YYYY-MM-DD)';
      ELSIF coalesce(fact->>'source_type','') = '' THEN reason := 'no source type (source_type)';
      ELSIF fid IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.v2_firms WHERE firm_id = fid) THEN reason := format('firm_id %s not found', fid);
      END IF;
    END IF;
    INSERT INTO public.v2_research_submissions (batch_id, firm_id, bot_key_id, target_box, payload)
      VALUES (batch, fid, bk.bot_key_id, coalesce(box,'?'), jsonb_build_object('target_table',tbl,'fact',coalesce(it->'fact','{}'::jsonb),'item_index',idx))
      RETURNING submission_id INTO sid;
    IF reason IS NULL AND tbl = 'v2_firms' AND fid IS NULL THEN
      UPDATE public.v2_research_submissions SET status = 'Held: new firm waits for the Checker (F1.3.1)' WHERE submission_id = sid;
      INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, submission_id, new_value, result)
        VALUES (bot, NULL, box, tbl, sid, it, 'Blocked: held, new firm waits for the Checker');
      held := held + 1;
      results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Held: new firm waits for the Checker (F1.3.1)','checker_queued','new-firm');
      CONTINUE;
    END IF;
    IF reason IS NULL THEN
      p := fact;
      IF fid IS NOT NULL THEN p := p || jsonb_build_object('firm_id', fid); END IF;
    END IF;
    IF reason IS NULL THEN
      IF (p->>'source_level') = '4' THEN p := p || '{"archived":true,"archive_reason":"L4 kept archived (R2)"}'; END IF;
      p := p || jsonb_build_object('submission_id', sid);
      SELECT string_agg(format('%I', key), ',') INTO cols FROM jsonb_object_keys(p) key;
      BEGIN
        EXECUTE format('INSERT INTO public.%I AS t (%s) SELECT %s FROM jsonb_populate_record(NULL::public.%I, $1) RETURNING to_jsonb(t)', tbl, cols, cols, tbl) INTO res USING p;
__EXC_OLD__
      UPDATE public.v2_research_submissions SET status = 'Rejected: '||reason WHERE submission_id = sid;
      INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, submission_id, new_value, result)
        VALUES (bot, fid, coalesce(box,'?'), coalesce(tbl,'?'), sid, it, 'Rejected: '||reason);
      rejn := rejn + 1;
      results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Rejected: '||reason);
      CONTINUE;
    END IF;
    newid := (res->>'row_id')::bigint;
    UPDATE public.v2_deals SET is_current = false, shown = false WHERE submission_id = sid;
    UPDATE public.v2_research_submissions SET status = 'Accepted' WHERE submission_id = sid;
    INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
      VALUES (bot, fid, box, tbl, newid, sid, NULL, res, 'Accepted');
    IF NOT EXISTS (SELECT 1 FROM jsonb_object_keys(p) key WHERE NOT (key = ANY(src_keys) OR key IN ('firm_id','submission_id','archived','archive_reason') OR key LIKE '%\_name')) THEN
      q_kind := 'name-only';
      INSERT INTO public.v2_checker_queue (submission_id, firm_id, kind, table_name, row_id, new_value) VALUES (sid, fid, 'name-only', tbl, newid, res);
__ACC_OLD__
  END LOOP;
  IF p_dry_run THEN RAISE EXCEPTION 'v2_dry_run_rollback'; END IF;
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'v2_dry_run_rollback' THEN RAISE; END IF;
  END;
  RETURN jsonb_strip_nulls(jsonb_build_object('ok', true, 'bot_id', bot, 'dry_run', p_dry_run, 'batch_id', CASE WHEN NOT p_dry_run THEN batch END,
    'accepted', acc, 'rejected', rejn, 'held', held, 'results', results));
END $function$;
"""

SCHEMA = r"""
create schema if not exists bots;
create table bots.ingest_keys (
  id uuid primary key,
  bot_id text,
  key_hash text,
  active boolean not null default true
);
create sequence public.v2_bot_keys_bot_key_id_seq;
create table public.v2_bot_keys (
  bot_key_id bigint primary key default nextval('public.v2_bot_keys_bot_key_id_seq'),
  bot_name text unique not null,
  key_hash text,
  frozen boolean not null default false,
  freeze_date timestamptz,
  freeze_reason text
);
create sequence public.v2_batch_seq;
create table public.v2_firms (firm_id bigint primary key);
create table public.v2_research_submissions (
  submission_id bigint generated by default as identity primary key,
  batch_id bigint,
  firm_id bigint,
  bot_key_id bigint,
  target_box text,
  payload jsonb,
  status text,
  received_at timestamptz not null default now()
);
create table public.v2_checker_queue (
  queue_id bigint generated by default as identity primary key,
  submission_id bigint,
  firm_id bigint,
  kind text,
  table_name text,
  row_id bigint,
  old_value jsonb,
  new_value jsonb,
  status text not null default 'open',
  archived boolean not null default false
);
create table public.v2_change_log (
  log_id bigint generated by default as identity primary key,
  actor text,
  firm_id bigint,
  box text,
  table_name text,
  row_id bigint,
  submission_id bigint,
  old_value jsonb,
  new_value jsonb,
  result text
);
create table public.v2_deals (
  row_id bigint generated by default as identity primary key,
  firm_id bigint,
  submission_id bigint,
  startup_name text,
  round_name text,
  deal_date date,
  deal_date_precision text,
  round_amount numeric,
  lead_investor text,
  source_url text,
  source_level smallint,
  source_date date,
  source_type text,
  source_owner text,
  is_current boolean not null default true,
  shown boolean not null default true,
  archived boolean not null default false,
  archive_reason text,
  check (round_amount is null or round_amount >= 0)
);
create unique index v2_deals_null_precision_round
  on public.v2_deals (firm_id, startup_name, round_name)
  where deal_date_precision is null;
create function public.v2_deals_block_triggerco() returns trigger language plpgsql as $$
begin
  if new.startup_name = 'TriggerCo' then
    raise exception 'duplicate guard collision';
  end if;
  return new;
end $$;
create trigger v2_deals_block_triggerco before insert on public.v2_deals
  for each row execute function public.v2_deals_block_triggerco();
"""


def block(text, tag):
    needle = f"${tag}$"
    start = text.index(needle) + len(needle)
    end = text.index(needle, start)
    return text[start:end]


def before_sql():
    sql = BEFORE_TEMPLATE
    for name, tag in (
        ("__DECL_OLD__", "decl_old"),
        ("__KEY_OLD__", "key_old"),
        ("__LOOP_OLD__", "loop_old"),
        ("__EXC_OLD__", "exc_old"),
        ("__ACC_OLD__", "acc_old"),
    ):
        sql = sql.replace(name, block(MIG, tag))
    return sql


def fact(**extra):
    row = {
        "source_url": "https://example.com/private-source",
        "source_level": "2",
        "source_date": "2026-11-08",
        "source_type": "Filing",
    }
    row.update(extra)
    return row


def item(table, fact_row, firm_id=7, box="D1", **extra):
    row = {"box": box, "table": table, "fact": fact_row}
    if firm_id is not None:
        row["firm_id"] = firm_id
    row.update(extra)
    return row


def submit(cur, key, items, dry=False):
    cur.execute(
        "select public.v2_research_submit(%s::uuid, %s::jsonb, %s)::text",
        (key, json.dumps(items), dry),
    )
    return json.loads(cur.fetchone()[0])


def test_the_path_is_one_reversible_patch_and_not_a_framework():
    for tag in ("key", "decl", "loop", "exc", "acc"):
        assert block(MIG, f"{tag}_old") == block(UNDO, f"{tag}_new")
        assert block(MIG, f"{tag}_new") == block(UNDO, f"{tag}_old")
    assert block(MIG, "key_new") == block(MIG, "key_old") + "\n  muse := bk.bot_key_id = 322 AND bot = 'external-muse-bot';"
    for tag in ("key_old", "loop_old", "exc_old", "acc_old"):
        assert block(MIG, tag) in SUBMIT_SRC
    assert block(MIG, "decl_old") in DOORS_SRC
    assert block(MIG, "decl_new").startswith(block(MIG, "decl_old"))
    assert "v2_publish_queue_item(qid)" in block(MIG, "acc_new")
    assert MIG.count("muse := bk.bot_key_id = 322 AND bot = 'external-muse-bot'") == 1
    low = MIG.lower()
    for banned in ("delete from", "truncate ", "drop table", "grant ", "create table", "ingest_auth", "ingest_paused"):
        assert banned not in low
    for tag in ("key_new", "decl_new", "loop_new", "exc_new", "acc_new"):
        piece = block(MIG, tag).lower()
        for banned in ("is_current", "shown =", "v2_lp_commitments", "v2_news_items", "investment staff",
                       "v2_firm_page", "->>'trusted'", "it->>'bot_id'", "delete from"):
            assert banned not in piece
    for batch in ("1414", "1415", "1416", "1417", "1422", "1424", "1427", "1429"):
        assert batch not in MIG and batch not in UNDO
    assert "nothing is deleted" in UNDO.lower()
    assert "create table" not in UNDO.lower()
    assert "to_regprocedure('public.v2_research_submit(uuid,jsonb,boolean)') is null" in MIG
    line = [ln for ln in GUIDE.splitlines() if ln.startswith("- **A3.3**")]
    assert len(line) == 1
    assert "bot_key_id 322" in line[0]
    assert "v2_publish_queue_item" in line[0]
    assert "rollbacks/20261109030000_v2_muse_trusted_publish.sql" in line[0]
    assert "rows already published stay" in line[0]
    assert "v2_checker_action" in DOOR
    assert "muse" not in DOOR.lower()


def test_authenticated_muse_publishes_valid_items_and_holds_flags():
    psycopg = pytest.importorskip("psycopg")
    try:
        conn = psycopg.connect(DSN)
    except Exception as err:
        pytest.skip(f"no database for the Muse path test: {err}")
    conn.autocommit = False
    try:
        cur = conn.cursor()
        cur.execute(SCHEMA)
        cur.execute(PUBLISH)
        publish_before = cur.execute("select pg_get_functiondef('public.v2_publish_queue_item(bigint)'::regprocedure)").fetchone()[0]
        cur.execute(before_sql())
        cur.execute(MIG)
        publish_after = cur.execute("select pg_get_functiondef('public.v2_publish_queue_item(bigint)'::regprocedure)").fetchone()[0]
        assert publish_after == publish_before
        body = cur.execute("select pg_get_functiondef('public.v2_research_submit(uuid,jsonb,boolean)'::regprocedure)").fetchone()[0]
        assert body.count("muse := bk.bot_key_id = 322 AND bot = 'external-muse-bot'") == 1
        cur.execute(MIG)
        assert cur.execute("select pg_get_functiondef('public.v2_research_submit(uuid,jsonb,boolean)'::regprocedure)").fetchone()[0] == body

        cur.execute("insert into public.v2_firms (firm_id) values (7)")
        cur.execute(
            """
            insert into bots.ingest_keys (id, bot_id, key_hash) values
              (%s, 'external-muse-bot', 'hash-muse'),
              (%s, 'external-research-bot-1', 'hash-conductor'),
              (%s, 'external-portal-one-bot', 'hash-portal')
            """,
            (MUSE, CONDUCTOR, PORTAL),
        )
        cur.execute(
            """
            insert into public.v2_bot_keys (bot_key_id, bot_name, key_hash) values
              (322, 'external-muse-bot', 'hash-muse'),
              (401, 'external-research-bot-1', 'hash-conductor'),
              (402, 'external-portal-one-bot', 'hash-portal')
            """
        )
        cur.execute("select setval('public.v2_bot_keys_bot_key_id_seq', 1000)")

        batch = submit(cur, MUSE, [
            item("v2_deals", fact(startup_name="Anduril", round_name="Series E", deal_date="2021-06-01", round_amount=100)),
            item("v2_deals", fact(startup_name="Anduril", round_name="Series E", deal_date="2024-06-01", round_amount=200)),
            item("v2_deals", fact(startup_name="BadAmount", round_name="Seed", deal_date="2023-01-01", round_amount=-1)),
            item("v2_deals", fact(startup_name="NoSource", round_name="Seed", deal_date="2023-01-01", round_amount=1, source_url="")),
            item("v2_deals", fact(startup_name="NameOnly")),
        ])
        assert batch["ok"] is True
        assert batch["accepted"] == 2
        assert batch["held"] == 1
        assert batch["rejected"] == 2
        assert batch["results"][0]["status"] == "Accepted"
        assert batch["results"][0]["note"] == "published on the Muse trusted path"
        assert "checker_queued" not in batch["results"][0]
        assert batch["results"][1]["status"].startswith("Held:")
        assert "duplicate" in batch["results"][1]["status"]
        assert batch["results"][2]["status"].startswith("Rejected:")
        assert "duplicate" not in batch["results"][2]["status"]
        assert batch["results"][3]["status"] == "Rejected: no source link (source_url)"
        assert batch["results"][4]["status"] == "Accepted"
        assert batch["results"][4]["checker_queued"] == "name-only"
        assert "note" not in batch["results"][4]

        cur.execute("select startup_name, deal_date::text, round_amount::int, is_current, shown, archived, source_url from v2_deals order by row_id")
        rows = cur.fetchall()
        assert rows[0] == ("Anduril", "2021-06-01", 100, True, True, False, "https://example.com/private-source")
        assert rows[1][0] == "NameOnly" and rows[1][3] is False and rows[1][4] is False
        assert [r[0] for r in rows] == ["Anduril", "NameOnly"]
        cur.execute("select kind, status from v2_checker_queue order by queue_id")
        assert cur.fetchall() == [("accepted-item", "passed"), ("name-only", "open")]
        cur.execute("select result from v2_change_log where result = 'Accepted: published on the Muse trusted path'")
        assert cur.fetchone()[0] == "Accepted: published on the Muse trusted path"
        cur.execute("select new_value->>'bot_key_id', new_value->>'publish' from v2_change_log where result = 'Accepted: published on the Muse trusted path'")
        assert cur.fetchone() == ("322", "Confirmed: published (deal shown, D1.8)")

        hidden = submit(cur, MUSE, [item("v2_deals", fact(startup_name="Quiet", round_name="Seed", lead_investor="Someone"))])
        assert hidden["results"][0]["note"] == "published on the Muse trusted path"
        cur.execute("select is_current, shown from v2_deals where startup_name = 'Quiet'")
        assert cur.fetchone() == (True, False)

        level4 = submit(cur, MUSE, [item("v2_deals", fact(startup_name="Archived", round_name="Seed", deal_date="2022-01-01", round_amount=5, source_level="4"))])
        assert "L4: kept archived (R2)" in level4["results"][0]["note"]
        assert "published on the Muse trusted path" in level4["results"][0]["note"]
        cur.execute("select is_current, shown, archived from v2_deals where startup_name = 'Archived'")
        assert cur.fetchone() == (False, False, True)

        flagged = submit(cur, MUSE, [item("v2_deals", fact(startup_name="TriggerCo", round_name="Seed", deal_date="2020-01-01", round_amount=5))])
        assert flagged["ok"] is True and flagged["held"] == 1 and flagged["accepted"] == 0
        assert flagged["results"][0]["status"].startswith("Held:")
        assert "duplicate guard collision" in flagged["results"][0]["status"]
        cur.execute("select count(*) from v2_deals where startup_name = 'TriggerCo'")
        assert cur.fetchone()[0] == 0

        fresh = submit(cur, CONDUCTOR, [item("v2_deals", fact(
            startup_name="Anduril", round_name="Series E", deal_date="2025-01-01", round_amount=300,
        ))])
        assert fresh["results"][0]["status"].startswith("Rejected:")
        assert "duplicate" in fresh["results"][0]["status"]
        cur.execute("select deal_date::text, round_amount::int from v2_deals where startup_name = 'Anduril'")
        assert cur.fetchall() == [("2021-06-01", 100)]

        other = submit(cur, CONDUCTOR, [item("v2_deals", fact(
            startup_name="ConductorCo", round_name="Seed", deal_date="2024-02-02", round_amount=10,
        ), trusted=True, bot_id="external-muse-bot", bot_key_id=322)])
        portal = submit(cur, PORTAL, [item("v2_deals", fact(
            startup_name="PortalCo", round_name="Seed", deal_date="2024-03-03", round_amount=10,
        ), trusted=True, bot_id="external-muse-bot")])
        assert other["results"][0]["checker_queued"] == "accepted-item"
        assert portal["results"][0]["checker_queued"] == "accepted-item"
        cur.execute("select startup_name, is_current from v2_deals where startup_name in ('ConductorCo','PortalCo') order by startup_name")
        assert cur.fetchall() == [("ConductorCo", False), ("PortalCo", False)]
        cur.execute("select status from v2_checker_queue q join v2_deals d on d.row_id = q.row_id where d.startup_name in ('ConductorCo','PortalCo') order by d.startup_name")
        assert cur.fetchall() == [("open",), ("open",)]

        new_firm = submit(cur, MUSE, [item("v2_firms", fact(legal_name="Not A Firm"), firm_id=None, firm_ref="not-a-firm", box="F1")])
        assert new_firm["results"][0]["status"] == "Held: new firm waits for the Checker (F1.3.1)"
        cur.execute("select count(*) from v2_firms")
        assert cur.fetchone()[0] == 1
        missing = submit(cur, MUSE, [item("v2_deals", fact(startup_name="Missing", round_name="Seed", deal_date="2024-01-01", round_amount=1), firm_id=999)])
        assert missing["results"][0]["status"] == "Rejected: firm_id 999 not found"

        cur.execute("savepoint frozen_key")
        cur.execute("update v2_bot_keys set frozen = true, freeze_date = now(), freeze_reason = 'test freeze' where bot_key_id = 322")
        before_deals = cur.execute("select count(*) from v2_deals").fetchone()[0]
        frozen = submit(cur, MUSE, [item("v2_deals", fact(startup_name="Frozen", round_name="Seed", deal_date="2024-01-01", round_amount=1))])
        assert frozen["ok"] is False
        assert frozen["error"].startswith("Key frozen:")
        assert cur.execute("select count(*) from v2_deals").fetchone()[0] == before_deals
        cur.execute("rollback to savepoint frozen_key")

        before_deals = cur.execute("select count(*) from v2_deals").fetchone()[0]
        dry = submit(cur, MUSE, [item("v2_deals", fact(startup_name="Dry", round_name="Seed", deal_date="2024-01-01", round_amount=1))], dry=True)
        assert dry["ok"] is True and dry["dry_run"] is True
        assert cur.execute("select count(*) from v2_deals").fetchone()[0] == before_deals

        cur.execute("update v2_bot_keys set bot_key_id = 999 where bot_name = 'external-muse-bot'")
        impostor_name = submit(cur, MUSE, [item("v2_deals", fact(startup_name="WrongId", round_name="Seed", deal_date="2024-04-04", round_amount=1))])
        assert impostor_name["results"][0]["checker_queued"] == "accepted-item"
        cur.execute("select is_current from v2_deals where startup_name = 'WrongId'")
        assert cur.fetchone()[0] is False
        cur.execute("update v2_bot_keys set bot_key_id = 998 where bot_name = 'external-muse-bot'")
        cur.execute("update v2_bot_keys set bot_key_id = 322 where bot_name = 'external-research-bot-1'")
        wrong_key_number = submit(cur, CONDUCTOR, [item("v2_deals", fact(startup_name="WrongName", round_name="Seed", deal_date="2024-05-05", round_amount=1))])
        assert wrong_key_number["results"][0]["checker_queued"] == "accepted-item"
        cur.execute("select is_current from v2_deals where startup_name = 'WrongName'")
        assert cur.fetchone()[0] is False
        cur.execute("update v2_bot_keys set bot_key_id = 401 where bot_name = 'external-research-bot-1'")
        cur.execute("update v2_bot_keys set bot_key_id = 322 where bot_name = 'external-muse-bot'")

        kept = cur.execute("select row_id, is_current, deal_date::text from v2_deals where startup_name = 'Anduril'").fetchone()
        cur.execute(UNDO)
        undone = cur.execute("select pg_get_functiondef('public.v2_research_submit(uuid,jsonb,boolean)'::regprocedure)").fetchone()[0]
        assert "published on the Muse trusted path" not in undone
        assert "muse-trusted-publish" not in undone
        assert cur.execute("select pg_get_functiondef('public.v2_publish_queue_item(bigint)'::regprocedure)").fetchone()[0] == publish_before
        later = submit(cur, MUSE, [item("v2_deals", fact(startup_name="AfterOff", round_name="Seed", deal_date="2024-06-06", round_amount=1))])
        assert later["results"][0]["status"] == "Accepted"
        assert later["results"][0]["checker_queued"] == "accepted-item"
        assert "note" not in later["results"][0]
        cur.execute("select is_current from v2_deals where startup_name = 'AfterOff'")
        assert cur.fetchone()[0] is False
        cur.execute("select status from v2_checker_queue q join v2_deals d on d.row_id = q.row_id where d.startup_name = 'AfterOff'")
        assert cur.fetchone()[0] == "open"
        assert cur.execute("select row_id, is_current, deal_date::text from v2_deals where startup_name = 'Anduril'").fetchone() == kept
        cur.execute("select is_current from v2_deals where startup_name = 'ConductorCo'")
        assert cur.fetchone()[0] is False
        cur.execute(UNDO)

        cur.execute(MIG)
        again = submit(cur, MUSE, [item("v2_deals", fact(startup_name="AfterOn", round_name="Seed", deal_date="2024-07-07", round_amount=1))])
        assert again["results"][0]["note"] == "published on the Muse trusted path"
        cur.execute("select is_current, shown from v2_deals where startup_name = 'AfterOn'")
        assert cur.fetchone() == (True, True)
    finally:
        conn.rollback()
        conn.close()
