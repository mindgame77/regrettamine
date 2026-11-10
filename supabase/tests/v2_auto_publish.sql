-- Proves the auto-publish switch on a database where 20261110120000_v2_auto_publish is installed.
-- The caller supplies the v2 tables (CI builds a small copy) and rolls the transaction back.
-- This file does not commit. A failing check raises. A passing run returns normally.
--
-- What it checks:
--   switch off: a new deal stays hidden and the queue stays open
--   on for firm 186 only: that firm's deal is visible immediately, another firm stays hidden
--   a rejected door item never goes live; an L4 row stays archived
--   a held empty firm field is written, and the queue stays open
--   a later held value overwrites it; a Checker reject puts the previous value back
--   a held empty startup website is filled; Checker confirm accepts that fill
--   backfill publishes waiting rows for an enabled firm and leaves other firms hidden
--   pull by bot and time hides only that slice; pull by firm hides the rest
--   a startup another firm already shows stays visible for that firm
--   restore brings the pulled rows back; a Checker-rejected row stays down
--   switching off hides nothing that is already up, and the next submission stays hidden

do $test$
declare
  v_bot uuid;
  v_bot_b uuid;
  v_checker uuid;
  v_bk bigint;
  v_bk_b bigint;
  v_startup bigint;
  v_shared bigint;
  v_private bigint;
  v_empty bigint;
  v_reply jsonb;
  v_deal bigint;
  v_row bigint;
  v_cur boolean;
  v_shown boolean;
  v_arch boolean;
  v_reason text;
  v_qid bigint;
  v_status text;
  v_sub_status text;
  v_name text;
  v_year smallint;
  v_keep bigint;
  v_off bigint;
  v_other bigint;
  v_manual_a bigint;
  v_manual_b bigint;
  v_firm8 bigint;
  v_src jsonb := jsonb_build_object(
    'source_url', 'https://portfolio.example.test/companies',
    'source_level', '2',
    'source_date', '2020-01-15',
    'source_type', 'Firm website');
  v_n int;
  v_out jsonb;
begin
  if to_regprocedure('public.v2_auto_publish_set(boolean,bigint[])') is null then
    raise exception 'v2_auto_publish is not installed';
  end if;

  select id into v_bot from bots.ingest_keys where name = 'v2-auto-publish-test-bot';
  select id into v_bot_b from bots.ingest_keys where name = 'v2-auto-publish-test-bot-b';
  select id into v_checker from bots.ingest_keys where name = 'v2-auto-publish-test-checker';
  if v_bot is null or v_bot_b is null or v_checker is null then
    raise exception 'test keys missing';
  end if;

  select startup_id into v_startup from public.v2_startups where startup_name = 'Auto Publish Existing';
  select startup_id into v_shared from public.v2_startups where startup_name = 'Auto Publish Shared';
  select startup_id into v_private from public.v2_startups where startup_name = 'Auto Publish Private';
  select startup_id into v_empty from public.v2_startups where startup_name = 'Auto Publish No Site';
  if v_startup is null or v_shared is null or v_private is null or v_empty is null then
    raise exception 'test startups missing';
  end if;

  if not exists (select 1 from public.v2_auto_publish where id and enabled = false and firm_ids = '{}') then
    raise exception 'switch must start off with an empty allowlist';
  end if;

  -- Switch off. A filed deal is stored, hidden, and queued.
  v_reply := public.v2_research_submit(v_bot, jsonb_build_array(jsonb_build_object(
    'table', 'v2_deals', 'box', 'D1', 'firm_id', '186',
    'fact', v_src || jsonb_build_object('startup_id', v_startup, 'deal_date', '2020-01-15', 'round_amount', 1000000)
  )), false);
  if coalesce(v_reply->>'ok', '') <> 'true' or coalesce(v_reply->>'accepted', '') <> '1' then
    raise exception 'off submit failed %', v_reply;
  end if;
  select d.deal_id, d.row_id, d.is_current, d.shown, d.archived
    into v_off, v_row, v_cur, v_shown, v_arch
    from public.v2_deals d where d.firm_id = 186 order by d.deal_id desc limit 1;
  if v_off is null or v_row is distinct from v_off or v_cur or v_shown or v_arch then
    raise exception 'off deal should stay hidden (deal % row % current % shown % archived %)', v_off, v_row, v_cur, v_shown, v_arch;
  end if;
  if not exists (
    select 1 from public.v2_checker_queue q
    where q.row_id = v_off and q.status = 'open' and not q.archived and q.table_name = 'v2_deals'
  ) then
    raise exception 'off deal was not queued';
  end if;
  if exists (select 1 from public.v2_auto_published) then
    raise exception 'switch off must not record an auto-publish';
  end if;

  v_out := public.v2_auto_publish_set(false, array[186]::bigint[]);
  if coalesce(v_out->>'enabled', '') <> 'false' or v_out->'firm_ids' <> '[186]'::jsonb then
    raise exception 'allowlist set failed %', v_out;
  end if;

  -- On for 186 only. This firm's next deal is visible. Firm 8 stays hidden.
  v_reply := public.v2_research_submit(v_bot, jsonb_build_array(jsonb_build_object(
    'table', 'v2_deals', 'box', 'D1', 'firm_id', '186',
    'fact', v_src || jsonb_build_object('startup_id', v_startup, 'deal_date', '2020-02-01', 'round_amount', 2000000)
  )), false);
  if coalesce(v_reply->>'accepted', '') <> '1' then
    raise exception 'on submit failed %', v_reply;
  end if;
  select d.deal_id, d.is_current, d.shown, d.archived, q.status
    into v_keep, v_cur, v_shown, v_arch, v_status
    from public.v2_deals d
    join public.v2_checker_queue q on q.row_id = d.deal_id and q.table_name = 'v2_deals'
   where d.firm_id = 186 and d.deal_id <> v_off
   order by d.deal_id desc limit 1;
  if not v_cur or not v_shown or v_arch or v_status <> 'open' then
    raise exception 'firm 186 deal should be live with an open queue (current % shown % archived % status %)', v_cur, v_shown, v_arch, v_status;
  end if;
  if not exists (select 1 from public.v2_auto_published ap where ap.row_id = v_keep and ap.live and ap.pulled_at is null) then
    raise exception 'live deal was not recorded as auto-published';
  end if;

  v_reply := public.v2_research_submit(v_bot, jsonb_build_array(jsonb_build_object(
    'table', 'v2_deals', 'box', 'D1', 'firm_id', '8',
    'fact', v_src || jsonb_build_object('startup_id', v_startup, 'deal_date', '2020-03-01', 'round_amount', 3000000)
  )), false);
  if coalesce(v_reply->>'accepted', '') <> '1' then
    raise exception 'firm 8 submit failed %', v_reply;
  end if;
  select d.deal_id, d.is_current, d.shown into v_other, v_cur, v_shown
    from public.v2_deals d where d.firm_id = 8 order by d.deal_id desc limit 1;
  if v_cur or v_shown then
    raise exception 'firm 8 must stay hidden while only 186 is on';
  end if;
  if exists (select 1 from public.v2_auto_published ap where ap.firm_id = 8) then
    raise exception 'firm 8 was auto-published';
  end if;
  select q.queue_id into v_qid from public.v2_checker_queue q
   where q.row_id = v_other and q.table_name = 'v2_deals' and q.status = 'open';
  v_reply := public.v2_checker_action(v_checker, 'verdict', jsonb_build_object(
    'id', v_qid, 'verdict', 'reject', 'reason', 'not part of this firm', 'sources', '[]'::jsonb
  ), false);
  if v_reply->>'outcome' <> 'Rejected: row archived, not published' then
    raise exception 'a row the switch did not publish must keep the old reject path %', v_reply;
  end if;

  v_reply := public.v2_research_submit(v_bot, jsonb_build_array(jsonb_build_object(
    'table', 'v2_deals', 'box', 'D1', 'firm_id', '186',
    'fact', v_src || jsonb_build_object('startup_id', v_startup, 'source_url', '')
  )), false);
  if coalesce(v_reply->>'rejected', '') <> '1' or v_reply->'results'->0->>'status' not like 'Rejected:%' then
    raise exception 'bad item should be rejected %', v_reply;
  end if;
  if (select count(*) from public.v2_deals where firm_id = 186 and is_current) <> 1 then
    raise exception 'a rejected item created a live deal';
  end if;

  v_reply := public.v2_research_submit(v_bot, jsonb_build_array(jsonb_build_object(
    'table', 'v2_deals', 'box', 'D1', 'firm_id', '186',
    'fact', (v_src || jsonb_build_object('startup_id', v_startup, 'deal_date', '2020-04-01', 'round_amount', 1))
            || jsonb_build_object('source_level', '4')
  )), false);
  if coalesce(v_reply->>'accepted', '') <> '1' then
    raise exception 'L4 submit failed %', v_reply;
  end if;
  select d.is_current, d.archived into v_cur, v_arch
    from public.v2_deals d where d.firm_id = 186 and d.deal_date = date '2020-04-01';
  if v_cur or not v_arch then
    raise exception 'L4 must stay archived (current % archived %)', v_cur, v_arch;
  end if;
  if exists (
    select 1 from public.v2_auto_published ap
    join public.v2_deals d on d.deal_id = ap.row_id
    where d.deal_date = date '2020-04-01'
  ) then
    raise exception 'L4 must not be marked auto-published';
  end if;

  -- Held empty firm fields are written. The bot still hears Held. The queue stays open.
  v_reply := public.v2_research_submit(v_bot, jsonb_build_array(jsonb_build_object(
    'table', 'v2_firms', 'box', 'F1', 'firm_id', '186',
    'fact', v_src || jsonb_build_object('source_url', 'https://www.paradigm.xyz/terms', 'legal_name', 'Paradigm Operations LP')
  )), false);
  if v_reply->'results'->0->>'status' <> 'Held: empty firm field waits for the Checker' then
    raise exception 'legal name should stay Held to the bot %', v_reply;
  end if;
  select f.legal_name into v_name from public.v2_firms f where f.firm_id = 186;
  if v_name is distinct from 'Paradigm Operations LP' then
    raise exception 'held legal name was not applied, got %', v_name;
  end if;
  select q.queue_id, q.status, s.status into v_qid, v_status, v_sub_status
    from public.v2_checker_queue q
    join public.v2_research_submissions s on s.submission_id = q.submission_id
   where q.firm_id = 186 and q.table_name = 'v2_firms' and q.new_value ? 'legal_name'
   order by q.queue_id desc limit 1;
  if v_status <> 'open' or v_sub_status <> 'Held: empty firm field waits for the Checker' then
    raise exception 'held legal name queue changed (queue % submission %)', v_status, v_sub_status;
  end if;

  v_reply := public.v2_research_submit(v_bot, jsonb_build_array(jsonb_build_object(
    'table', 'v2_firms', 'box', 'F1', 'firm_id', '186',
    'fact', v_src || jsonb_build_object('source_url', 'https://www.paradigm.xyz/about', 'founded_year', 2018)
  )), false);
  if v_reply->'results'->0->>'status' <> 'Held: empty firm field waits for the Checker' then
    raise exception 'founded year should stay Held %', v_reply;
  end if;
  select f.founded_year into v_year from public.v2_firms f where f.firm_id = 186;
  if v_year is distinct from 2018 then
    raise exception 'held founded year was not applied, got %', v_year;
  end if;

  v_reply := public.v2_research_submit(v_bot, jsonb_build_array(jsonb_build_object(
    'table', 'v2_firms', 'box', 'F1', 'firm_id', '186',
    'fact', v_src || jsonb_build_object('source_url', 'https://www.paradigm.xyz/about', 'legal_name', 'Other Name LP')
  )), false);
  if v_reply->'results'->0->>'status' not like 'Held:%' then
    raise exception 'changed legal name should stay Held %', v_reply;
  end if;
  select f.legal_name into v_name from public.v2_firms f where f.firm_id = 186;
  if v_name is distinct from 'Other Name LP' then
    raise exception 'changed legal name was not applied, got %', v_name;
  end if;
  select q.queue_id into v_qid
    from public.v2_checker_queue q
   where q.firm_id = 186 and q.table_name = 'v2_firms' and q.new_value->>'legal_name' = 'Other Name LP'
   order by q.queue_id desc limit 1;
  v_reply := public.v2_checker_action(v_checker, 'verdict', jsonb_build_object(
    'id', v_qid, 'verdict', 'reject', 'reason', 'name does not match the source', 'sources', '[]'::jsonb
  ), false);
  if coalesce(v_reply->>'ok', '') <> 'true' or v_reply->>'outcome' <> 'Rejected: auto-published value reverted' then
    raise exception 'checker reject of legal name failed %', v_reply;
  end if;
  select f.legal_name into v_name from public.v2_firms f where f.firm_id = 186;
  if v_name is distinct from 'Paradigm Operations LP' then
    raise exception 'checker reject should restore the prior legal name, got %', v_name;
  end if;
  if (select status from public.v2_checker_queue where queue_id = v_qid) <> 'failed' then
    raise exception 'rejected queue item should be failed';
  end if;

  -- Checker reject of a live deal archives it, so both page predicates drop it.
  select q.queue_id into v_qid from public.v2_checker_queue q
   where q.row_id = v_keep and q.table_name = 'v2_deals' and q.status = 'open';
  v_reply := public.v2_checker_action(v_checker, 'verdict', jsonb_build_object(
    'id', v_qid, 'verdict', 'reject', 'reason', 'deal was not announced', 'sources', '[]'::jsonb
  ), false);
  if v_reply->>'outcome' <> 'Rejected: auto-published row taken down' then
    raise exception 'checker reject of deal failed %', v_reply;
  end if;
  select d.is_current, d.shown, d.archived, d.archive_reason into v_cur, v_shown, v_arch, v_reason
    from public.v2_deals d where d.deal_id = v_keep;
  if v_cur or v_shown or not v_arch or v_reason not like 'Checker rejected:%' then
    raise exception 'rejected deal should be archived (current % shown % archived % reason %)', v_cur, v_shown, v_arch, v_reason;
  end if;
  if (v_cur and not v_arch and coalesce(v_shown, true))
     or (((coalesce(v_shown, true) and v_cur and not v_arch) or v_arch)
         and coalesce(v_reason, '') !~* '^(checker rejected|superseded)') then
    raise exception 'rejected deal still matches a page predicate';
  end if;

  select q.queue_id into v_qid from public.v2_checker_queue q
   where q.firm_id = 186 and q.table_name = 'v2_firms' and q.new_value ? 'founded_year' and q.status = 'open'
   order by q.queue_id desc limit 1;
  v_reply := public.v2_checker_action(v_checker, 'verdict', jsonb_build_object(
    'id', v_qid, 'verdict', 'confirm', 'reason', 'year matches the about page',
    'sources', jsonb_build_array('https://www.paradigm.xyz/about')
  ), false);
  if coalesce(v_reply->>'ok', '') <> 'true' or v_reply->>'outcome' not like 'Confirmed: applied%' then
    raise exception 'confirm of an already-applied year failed %', v_reply;
  end if;
  if (select founded_year from public.v2_firms where firm_id = 186) is distinct from 2018 then
    raise exception 'confirm changed the founded year';
  end if;

  v_reply := public.v2_research_submit(v_bot, jsonb_build_array(jsonb_build_object(
    'table', 'v2_startups', 'box', 'S1', 'firm_id', '186',
    'fact', v_src || jsonb_build_object(
      'startup_id', v_empty, 'website_url', 'https://empty-startup.example.test')
  )), false);
  if v_reply->'results'->0->>'status' <> 'Held: empty startup website waits for the Checker' then
    raise exception 'website fill should stay Held %', v_reply;
  end if;
  if (select website_url from public.v2_startups where startup_id = v_empty) is distinct from 'https://empty-startup.example.test' then
    raise exception 'held website was not filled';
  end if;
  select q.queue_id into v_qid from public.v2_checker_queue q
   where q.table_name = 'v2_startups' and q.row_id = v_empty and q.status = 'open'
   order by q.queue_id desc limit 1;
  v_reply := public.v2_checker_action(v_checker, 'verdict', jsonb_build_object(
    'id', v_qid, 'verdict', 'confirm', 'reason', 'site matches the company page',
    'sources', jsonb_build_array('https://empty-startup.example.test')
  ), false);
  if v_reply->>'outcome' <> 'Confirmed: website already filled' then
    raise exception 'confirm of an already-filled website failed %', v_reply;
  end if;

  -- Backfill publishes rows that were filed while the switch was off, and skips other firms.
  select bot_key_id into v_bk from public.v2_bot_keys where bot_name = 'v2-auto-publish-test-bot';
  v_reply := public.v2_research_submit(v_bot_b, jsonb_build_array(jsonb_build_object(
    'table', 'v2_deals', 'box', 'D1', 'firm_id', '8',
    'fact', v_src || jsonb_build_object('startup_id', v_startup, 'deal_date', '2020-05-01', 'round_amount', 5)
  )), false);
  if coalesce(v_reply->>'accepted', '') <> '1' then
    raise exception 'second bot submit failed %', v_reply;
  end if;
  select bot_key_id into v_bk_b from public.v2_bot_keys where bot_name = 'v2-auto-publish-test-bot-b';

  insert into public.v2_research_submissions (firm_id, bot_key_id, target_box, payload, status, received_at)
  values (186, v_bk, 'D2', '{}'::jsonb, 'Accepted', '2026-11-01 12:00:00+00')
  returning submission_id into v_n;
  insert into public.v2_deals (
    firm_id, startup_id, submission_id, source_url, source_level, source_date, source_type, source_owner,
    deal_date, round_amount)
  values (186, v_startup, v_n, 'https://portfolio.example.test/a', 2, date '2020-01-15', 'Firm website', 'bot-a',
          date '2020-06-01', 6)
  returning deal_id into v_manual_a;
  insert into public.v2_checker_queue (submission_id, firm_id, kind, table_name, row_id, status)
  values (v_n, 186, 'accepted-item', 'v2_deals', v_manual_a, 'open');

  insert into public.v2_research_submissions (firm_id, bot_key_id, target_box, payload, status, received_at)
  values (186, v_bk_b, 'D2', '{}'::jsonb, 'Accepted', '2026-11-01 18:00:00+00')
  returning submission_id into v_n;
  insert into public.v2_deals (
    firm_id, startup_id, submission_id, source_url, source_level, source_date, source_type, source_owner,
    deal_date, round_amount)
  values (186, v_startup, v_n, 'https://portfolio.example.test/b', 2, date '2020-01-15', 'Firm website', 'bot-b',
          date '2020-07-01', 7)
  returning deal_id into v_manual_b;
  insert into public.v2_checker_queue (submission_id, firm_id, kind, table_name, row_id, status)
  values (v_n, 186, 'accepted-item', 'v2_deals', v_manual_b, 'open');

  insert into public.v2_research_submissions (firm_id, bot_key_id, target_box, payload, status, received_at)
  values (186, v_bk, 'S2', '{}'::jsonb, 'Accepted', '2026-11-01 12:30:00+00')
  returning submission_id into v_n;
  insert into public.v2_checker_queue (submission_id, firm_id, kind, table_name, row_id, status)
  values (v_n, 186, 'accepted-item', 'v2_startups', v_shared, 'open');
  insert into public.v2_deals (
    firm_id, startup_id, submission_id, source_url, source_level, source_date, source_type, source_owner,
    deal_date, round_amount, is_current, shown)
  values (8, v_shared, v_n, 'https://accel.example.test/shared', 2, date '2020-01-15', 'Firm website', 'accel',
          date '2019-01-01', 9, true, true)
  returning deal_id into v_firm8;

  insert into public.v2_research_submissions (firm_id, bot_key_id, target_box, payload, status, received_at)
  values (186, v_bk, 'S3', '{}'::jsonb, 'Accepted', '2026-11-03 12:40:00+00')
  returning submission_id into v_n;
  insert into public.v2_checker_queue (submission_id, firm_id, kind, table_name, row_id, status)
  values (v_n, 186, 'accepted-item', 'v2_startups', v_private, 'open');

  v_out := public.v2_auto_publish_backfill(8);
  if coalesce(v_out->>'ok', '') <> 'false' then
    raise exception 'backfill of a firm that is off should refuse %', v_out;
  end if;
  v_out := public.v2_auto_publish_backfill(186);
  if coalesce((v_out->>'published')::int, 0) < 4 or coalesce((v_out->>'errors')::int, 0) <> 0 then
    raise exception 'backfill failed %', v_out;
  end if;
  if not (select is_current from public.v2_deals where deal_id = v_off) then
    raise exception 'backfill should publish the deal that was filed while the switch was off';
  end if;
  if not (select is_current and shown from public.v2_deals where deal_id = v_manual_a) then
    raise exception 'backfill missed bot A';
  end if;
  if not (select is_current and shown from public.v2_deals where deal_id = v_manual_b) then
    raise exception 'backfill missed bot B';
  end if;
  if (select is_current from public.v2_deals where deal_id = v_other) then
    raise exception 'backfill published firm 8';
  end if;
  if not (select is_current from public.v2_startups where startup_id = v_shared) then
    raise exception 'backfill should show the shared startup';
  end if;
  if not (select is_current from public.v2_startups where startup_id = v_private) then
    raise exception 'backfill should show the private startup';
  end if;
  if not (select is_current and shown and not archived from public.v2_deals where deal_id = v_firm8) then
    raise exception 'firm 8 existing deal was disturbed by backfill';
  end if;
  v_out := public.v2_auto_publish_backfill(186);
  if coalesce((v_out->>'published')::int, 0) <> 0 then
    raise exception 'second backfill should not publish again %', v_out;
  end if;

  -- Pull one bot inside one day. The other bot, and firm 8, stay up.
  v_out := public.v2_auto_publish_pull(null, v_bk, '2026-11-01 00:00:00+00', '2026-11-02 00:00:00+00');
  if coalesce((v_out->>'hidden')::int, 0) < 1 then
    raise exception 'bot/time pull hid nothing %', v_out;
  end if;
  if (select is_current from public.v2_deals where deal_id = v_manual_a) then
    raise exception 'bot A deal should be hidden';
  end if;
  if not (select is_current and shown from public.v2_deals where deal_id = v_manual_b) then
    raise exception 'bot B deal should stay up';
  end if;
  if not (select is_current from public.v2_startups where startup_id = v_private) then
    raise exception 'private startup is outside this pull';
  end if;
  -- The shared startup was filed by bot A in that window. Another firm shows it, so it stays.
  if not (select s.is_current and not s.archived from public.v2_startups s where s.startup_id = v_shared) then
    raise exception 'shared startup disappeared for the other firm';
  end if;
  if not (select d.is_current and not d.archived and coalesce(d.shown, true) from public.v2_deals d where d.deal_id = v_firm8) then
    raise exception 'firm 8 deal disappeared';
  end if;

  v_out := public.v2_auto_publish_pull(186, null, null, null);
  if (select is_current from public.v2_deals where deal_id = v_manual_b) then
    raise exception 'firm pull should hide bot B';
  end if;
  if (select is_current from public.v2_startups where startup_id = v_private) then
    raise exception 'private startup should hide on a firm pull';
  end if;
  if not (select is_current and not archived from public.v2_startups where startup_id = v_shared) then
    raise exception 'firm pull hid a startup another firm still shows';
  end if;
  if not (select is_current and shown and not archived from public.v2_deals where deal_id = v_firm8) then
    raise exception 'firm pull hid the other firm deal';
  end if;
  if (select legal_name from public.v2_firms where firm_id = 186) is not null then
    raise exception 'firm pull should revert the auto-applied legal name';
  end if;
  if (select founded_year from public.v2_firms where firm_id = 186) is not null then
    raise exception 'firm pull should revert the auto-applied founded year';
  end if;
  if (select website_url from public.v2_startups where startup_id = v_empty) is not null then
    raise exception 'firm pull should revert the auto-applied website';
  end if;
  if (select status from public.v2_checker_queue where row_id = v_manual_b and table_name = 'v2_deals') <> 'open' then
    raise exception 'pull must leave the queue open';
  end if;
  -- Pulled deal is absent from the live deal list and from the archived-or-current sector fallback.
  select d.is_current, d.shown, d.archived, d.archive_reason into v_cur, v_shown, v_arch, v_reason
    from public.v2_deals d where d.deal_id = v_manual_b;
  if (v_cur and not v_arch and coalesce(v_shown, true))
     or (((coalesce(v_shown, true) and v_cur and not v_arch) or v_arch)
         and coalesce(v_reason, '') !~* '^(checker rejected|superseded)') then
    raise exception 'pulled deal still matches a page predicate';
  end if;

  v_out := public.v2_auto_publish_backfill(186);
  if coalesce((v_out->>'published')::int, 0) <> 0 then
    raise exception 'backfill must not republish a pull %', v_out;
  end if;
  if (select is_current from public.v2_deals where deal_id = v_manual_b) then
    raise exception 'backfill brought a pulled deal back';
  end if;

  v_out := public.v2_auto_publish_restore(186, null, null, null);
  if coalesce((v_out->>'restored')::int, 0) < 1 then
    raise exception 'restore failed %', v_out;
  end if;
  if not (select is_current and shown from public.v2_deals where deal_id = v_manual_a) then
    raise exception 'restore missed bot A';
  end if;
  if not (select is_current and shown from public.v2_deals where deal_id = v_manual_b) then
    raise exception 'restore missed bot B';
  end if;
  if not (select is_current from public.v2_startups where startup_id = v_private) then
    raise exception 'restore missed the private startup';
  end if;
  if (select legal_name from public.v2_firms where firm_id = 186) is distinct from 'Paradigm Operations LP' then
    raise exception 'restore missed the legal name';
  end if;
  if (select founded_year from public.v2_firms where firm_id = 186) is distinct from 2018 then
    raise exception 'restore missed the founded year';
  end if;
  if (select website_url from public.v2_startups where startup_id = v_empty) is distinct from 'https://empty-startup.example.test' then
    raise exception 'restore missed the startup website';
  end if;
  if (select archived from public.v2_deals where deal_id = v_keep) is not true then
    raise exception 'restore brought back a Checker-rejected deal';
  end if;
  if (select status from public.v2_checker_queue where row_id = v_manual_b and table_name = 'v2_deals') <> 'open' then
    raise exception 'restore should leave the queue open';
  end if;

  -- Global on publishes a new firm 8 row. Turning the switch off leaves it up and hides the next 186 row.
  perform public.v2_auto_publish_set(true, '{}'::bigint[]);
  v_reply := public.v2_research_submit(v_bot, jsonb_build_array(jsonb_build_object(
    'table', 'v2_deals', 'box', 'D1', 'firm_id', '8',
    'fact', v_src || jsonb_build_object('startup_id', v_startup, 'deal_date', '2020-08-01', 'round_amount', 8)
  )), false);
  if coalesce(v_reply->>'accepted', '') <> '1' then
    raise exception 'global submit failed %', v_reply;
  end if;
  select d.deal_id into v_deal from public.v2_deals d
   where d.firm_id = 8 and d.deal_date = date '2020-08-01';
  if not (select is_current and shown from public.v2_deals where deal_id = v_deal) then
    raise exception 'global on should publish firm 8';
  end if;
  perform public.v2_auto_publish_set(false, '{}'::bigint[]);
  if (select is_current from public.v2_deals where deal_id = v_manual_b) is not true then
    raise exception 'turning the switch off hid a row that was already up';
  end if;
  v_reply := public.v2_research_submit(v_bot, jsonb_build_array(jsonb_build_object(
    'table', 'v2_deals', 'box', 'D1', 'firm_id', '186',
    'fact', v_src || jsonb_build_object('startup_id', v_startup, 'deal_date', '2020-09-01', 'round_amount', 9)
  )), false);
  if coalesce(v_reply->>'accepted', '') <> '1' then
    raise exception 'submit after switch off failed %', v_reply;
  end if;
  if (select is_current from public.v2_deals where firm_id = 186 and deal_date = date '2020-09-01') then
    raise exception 'switch off should hide the next submission';
  end if;
  if exists (
    select 1 from public.v2_auto_published ap
    join public.v2_deals d on d.deal_id = ap.row_id
    where d.deal_date = date '2020-09-01'
  ) then
    raise exception 'switch off recorded an auto-publish';
  end if;

  if has_function_privilege('bot_writer', 'public.v2_auto_publish_set(boolean,bigint[])', 'execute')
     or has_function_privilege('bot_writer', 'public.v2_auto_publish_apply_queue(bigint)', 'execute')
     or has_table_privilege('bot_writer', 'public.v2_auto_publish', 'select') then
    raise exception 'a research bot can reach the switch';
  end if;
  if has_function_privilege('anon', 'public.v2_auto_publish_set(boolean,bigint[])', 'execute')
     or has_function_privilege('anon', 'public.v2_auto_publish_backfill(bigint)', 'execute')
     or has_function_privilege('anon', 'public.v2_auto_publish_pull(bigint,bigint,timestamptz,timestamptz)', 'execute')
     or has_function_privilege('anon', 'public.v2_auto_publish_apply_queue(bigint)', 'execute')
     or has_table_privilege('anon', 'public.v2_auto_publish', 'select')
     or has_table_privilege('authenticated', 'public.v2_auto_published', 'select') then
    raise exception 'anon or authenticated can reach the switch';
  end if;
  if not has_function_privilege('service_role', 'public.v2_auto_publish_set(boolean,bigint[])', 'execute') then
    raise exception 'service_role cannot run the switch';
  end if;
  if exists (select 1 from pg_policies where tablename in ('v2_auto_publish', 'v2_auto_published')) then
    raise exception 'switch tables should have no policies';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.v2_auto_publish'::regclass)
     or not (select relrowsecurity from pg_class where oid = 'public.v2_auto_published'::regclass) then
    raise exception 'RLS is off';
  end if;
  begin
    update public.v2_change_log set result = 'Accepted' where log_id = (select min(log_id) from public.v2_change_log);
    raise exception 'change log accepted an update';
  exception when others then
    if sqlerrm = 'change log accepted an update' then
      raise;
    end if;
  end;
end
$test$;
