-- Dry-run cases for the startup website identity rules in v2_research_submit.
-- Run this on a database that already has the v2 schema and the new function.
-- The checks insert fixture rows, then roll them back. A passing run keeps nothing.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/v2_startup_website_identity.sql
--
-- The unique-violation race case commits one throwaway startup through a second
-- connection (dblink), then deletes it. Leave it off unless this is a copy you
-- can write to, the dblink extension is already installed, and you turn it on
-- in the same session before this file:
--
--   SELECT set_config('v2.run_startup_race_test', 'on', false);
--
-- What it checks:
--   no website, blank website, hosted-platform host (and a subdomain of one)
--   exact domain match, www / https / path / query variants
--   port, trailing dot, and query-only spellings of a domain the column stores
--   subdomain does not match, same name with a new domain does insert
--   an archived row with that domain does not match
--   a batch whose matched startup ref is used by a v2_deals item
--   website fill for an existing startup_id is unchanged
--   this website rejection does not count toward the per-firm freeze; other rejections still do
--   the unique-violation race path, when the setting above is on

-- The race trigger has to be committed before the test transaction takes locks
-- on v2_startups. Creating it inside that transaction deadlocks the plant insert.
do $race_setup$
begin
  if current_setting('v2.run_startup_race_test', true) is distinct from 'on' then
    return;
  end if;
  if to_regprocedure('dblink_connect(text,text)') is null then
    raise exception 'race case needs the dblink extension installed already';
  end if;
  perform dblink_connect('race_setup', 'dbname=' || current_database());
  perform dblink_exec('race_setup', 'drop trigger if exists v2_startup_race_plant on public.v2_startups');
  perform dblink_exec('race_setup', $plant$
    create or replace function public.v2_startup_race_plant() returns trigger
    language plpgsql as $body$
    begin
      if new.website_url like '%v2-submit-race-test.invalid%'
         and current_setting('application_name', true) is distinct from 'v2_race_planter' then
        perform dblink_exec('race', 'set application_name = ''v2_race_planter''');
        perform dblink_exec('race', format(
          'insert into public.v2_startups (source_url, source_date, source_type, source_owner, source_level, submission_id, startup_name, website_url) values (%L, date %L, %L, %L, 2, %s, %L, %L)',
          'https://portfolio.example.test/race', '2026-11-01', 'Firm website', 'v2-race',
          current_setting('v2.race_submission_id'), 'Race Planted', 'https://v2-submit-race-test.invalid/path'));
      end if;
      return new;
    end
    $body$
  $plant$);
  perform dblink_exec('race_setup', 'create trigger v2_startup_race_plant before insert on public.v2_startups for each row execute function public.v2_startup_race_plant()');
  perform dblink_disconnect('race_setup');
end
$race_setup$;

do $test$
declare
  v_key uuid;
  v_bot text := 'v2-startup-website-identity-test';
  v_firm bigint;
  v_bk bigint;
  v_sub bigint;
  v_existing bigint;
  v_empty bigint;
  v_archived bigint;
  v_ported bigint;
  v_reply jsonb;
  v_item jsonb;
  v_deal jsonb;
  v_src jsonb := jsonb_build_object(
    'source_url', 'https://portfolio.example.test/companies',
    'source_level', '2',
    'source_date', '2026-11-01',
    'source_type', 'Firm website');
  v_reason text := 'website_url required: find this startup''s website or skip the startup and its deal';
  v_startups int;
  v_queue int;
  v_logs int;
  v_name text;
  v_site text;
  v_current boolean;
  v_shown boolean;
  v_deal_startup bigint;
  v_new_id bigint;
  v_plant bigint;
  v_race boolean := current_setting('v2.run_startup_race_test', true) = 'on';
  v_race_firm bigint;
  v_race_key bigint;
  v_race_sub bigint;
begin
  insert into bots.ingest_keys (name, key_hash, bot_id)
  values ('v2 startup website identity test', 'test-hash-not-a-secret', v_bot)
  returning id into v_key;

  insert into public.v2_firms (display_name, slug, firm_status)
  values ('Website Identity Test Firm', 'v2-website-identity-' || gen_random_uuid()::text, 'Active')
  returning firm_id into v_firm;

  insert into public.v2_bot_keys (bot_name, key_hash)
  values (v_bot, 'test-hash-not-a-secret')
  returning bot_key_id into v_bk;

  insert into public.v2_research_submissions (batch_id, firm_id, bot_key_id, target_box, payload, status)
  values (nextval('public.v2_batch_seq'), v_firm, v_bk, 'F2', '{"fixture":true}'::jsonb, 'Accepted')
  returning submission_id into v_sub;

  insert into public.v2_startups (
    source_url, source_date, source_type, source_owner, source_level, submission_id,
    startup_name, website_url, is_current)
  values (
    'https://portfolio.example.test/existing', date '2026-11-01', 'Firm website', v_bot, 2, v_sub,
    'Existing Acme', 'https://www.acme.test/about', true)
  returning startup_id into v_existing;

  insert into public.v2_startups (
    source_url, source_date, source_type, source_owner, source_level, submission_id,
    startup_name, website_url, is_current)
  values (
    'https://portfolio.example.test/empty', date '2026-11-01', 'Firm website', v_bot, 2, v_sub,
    'Needs A Site', null, true)
  returning startup_id into v_empty;

  insert into public.v2_startups (
    source_url, source_date, source_type, source_owner, source_level, submission_id,
    startup_name, website_url, archived, archive_reason)
  values (
    'https://portfolio.example.test/archived', date '2026-11-01', 'Firm website', v_bot, 2, v_sub,
    'Archived Co', 'https://archived.test/old', true, 'test archive')
  returning startup_id into v_archived;

  insert into public.v2_startups (
    source_url, source_date, source_type, source_owner, source_level, submission_id,
    startup_name, website_url, is_current)
  values (
    'https://portfolio.example.test/ported', date '2026-11-01', 'Firm website', v_bot, 2, v_sub,
    'Ported Co', 'https://ported.test:443/a', true)
  returning startup_id into v_ported;

  select count(*) into v_startups from public.v2_startups;
  select count(*) into v_queue from public.v2_checker_queue;
  select count(*) into v_logs from public.v2_change_log;

  -- 1. No website, and a blank website. Same rejection. Nothing is queued.
  v_reply := public.v2_research_submit(v_key, jsonb_build_array(
    jsonb_build_object('firm_id', v_firm, 'box', 'F2', 'table', 'v2_startups', 'ref', 'nosite',
      'fact', v_src || jsonb_build_object('startup_name', 'No Site Co')),
    jsonb_build_object('firm_id', v_firm, 'box', 'F2', 'table', 'v2_startups',
      'fact', v_src || jsonb_build_object('startup_name', 'Blank Site Co', 'website_url', '   '))
  ), true);
  if v_reply->>'ok' is distinct from 'true' or v_reply->>'dry_run' is distinct from 'true' then
    raise exception 'no website: bad envelope %', v_reply;
  end if;
  if v_reply->'results'->0->>'status' is distinct from 'Rejected: ' || v_reason
     or v_reply->'results'->1->>'status' is distinct from 'Rejected: ' || v_reason
     or (v_reply->>'rejected')::int <> 2 or (v_reply->>'accepted')::int <> 0 then
    raise exception 'no website: %', v_reply;
  end if;
  if (select count(*) from public.v2_startups) <> v_startups
     or (select count(*) from public.v2_checker_queue) <> v_queue
     or (select count(*) from public.v2_change_log) <> v_logs then
    raise exception 'no website dry run wrote rows';
  end if;

  -- 2. Hosted-platform domain, including a subdomain and a www host. Not a suffix false positive.
  v_reply := public.v2_research_submit(v_key, jsonb_build_array(
    jsonb_build_object('firm_id', v_firm, 'box', 'F2', 'table', 'v2_startups',
      'fact', v_src || jsonb_build_object('startup_name', 'Link', 'website_url', 'https://linktr.ee/someone')),
    jsonb_build_object('firm_id', v_firm, 'box', 'F2', 'table', 'v2_startups',
      'fact', v_src || jsonb_build_object('startup_name', 'Hub', 'website_url', 'https://acme.github.com/acme')),
    jsonb_build_object('firm_id', v_firm, 'box', 'F2', 'table', 'v2_startups',
      'fact', v_src || jsonb_build_object('startup_name', 'Social', 'website_url', 'https://www.linkedin.com/company/acme')),
    jsonb_build_object('firm_id', v_firm, 'box', 'F2', 'table', 'v2_startups',
      'fact', v_src || jsonb_build_object('startup_name', 'Not Github', 'website_url', 'https://mygithub.com')),
    jsonb_build_object('firm_id', v_firm, 'box', 'F2', 'table', 'v2_startups',
      'fact', v_src || jsonb_build_object('startup_name', 'Box', 'website_url', 'https://box.com'))
  ), true);
  if v_reply->'results'->0->>'status' is distinct from 'Rejected: ' || v_reason
     or v_reply->'results'->1->>'status' is distinct from 'Rejected: ' || v_reason
     or v_reply->'results'->2->>'status' is distinct from 'Rejected: ' || v_reason then
    raise exception 'platform domain: %', v_reply;
  end if;
  if v_reply->'results'->3->>'status' is distinct from 'Accepted'
     or v_reply->'results'->3->>'checker_queued' is distinct from 'accepted-item'
     or v_reply->'results'->3 ? 'matched_startup_id'
     or v_reply->'results'->4->>'status' is distinct from 'Accepted'
     or v_reply->'results'->4->>'checker_queued' is distinct from 'accepted-item' then
    raise exception 'platform lookalikes should insert: %', v_reply;
  end if;

  -- 3 and 4. Exact domain, and www / https / path / query variants. Names differ. No checker queue.
  v_reply := public.v2_research_submit(v_key, jsonb_build_array(
    jsonb_build_object('firm_id', v_firm, 'box', 'F2', 'table', 'v2_startups', 'ref', 'exact',
      'fact', v_src || jsonb_build_object('startup_name', 'Acme Other Name', 'website_url', 'https://acme.test/about')),
    jsonb_build_object('firm_id', v_firm, 'box', 'F2', 'table', 'v2_startups',
      'fact', v_src || jsonb_build_object('startup_name', 'Acme Variant', 'website_url', 'HTTP://WWW.ACME.test/pricing?x=1#top')),
    jsonb_build_object('firm_id', v_firm, 'box', 'F2', 'table', 'v2_startups',
      'fact', v_src || jsonb_build_object('startup_name', 'Acme Port', 'website_url', 'https://acme.test:443/x')),
    jsonb_build_object('firm_id', v_firm, 'box', 'F2', 'table', 'v2_startups',
      'fact', v_src || jsonb_build_object('startup_name', 'Acme Dot', 'website_url', 'https://acme.test.')),
    jsonb_build_object('firm_id', v_firm, 'box', 'F2', 'table', 'v2_startups',
      'fact', v_src || jsonb_build_object('startup_name', 'Acme Query', 'website_url', 'https://acme.test?ref=1'))
  ), true);
  for v_item in select value from jsonb_array_elements(v_reply->'results') loop
    if v_item->>'status' is distinct from 'Accepted'
       or (v_item->>'matched_startup_id')::bigint is distinct from v_existing
       or (v_item->>'row_id')::bigint is distinct from v_existing
       or v_item ? 'checker_queued'
       or v_item->>'note' not like format('matched existing startup %s by website%%', v_existing)
       or position('Acme' in v_item->>'note') = 0
       or position('Existing Acme' in v_item->>'note') = 0 then
      raise exception 'domain match: %', v_item;
    end if;
  end loop;
  if (select count(*) from public.v2_startups) <> v_startups then
    raise exception 'domain match dry run inserted a startup';
  end if;

  -- A row stored with a port in its generated domain still matches the host without the port.
  -- A query or trailing dot with no path cannot be stored: v2_startups.website_url rejects that shape.
  -- Those spellings are still matched against a normal domain above.
  v_reply := public.v2_research_submit(v_key, jsonb_build_array(
    jsonb_build_object('firm_id', v_firm, 'box', 'F2', 'table', 'v2_startups',
      'fact', v_src || jsonb_build_object('startup_name', 'Plain Port', 'website_url', 'https://ported.test/home'))
  ), true);
  if (v_reply->'results'->0->>'matched_startup_id')::bigint is distinct from v_ported
     or v_reply->'results'->0 ? 'checker_queued' then
    raise exception 'stored port should match the host: %', v_reply;
  end if;

  -- 5. Subdomain stays distinct and is inserted. Archived domain does not block a new row.
  v_reply := public.v2_research_submit(v_key, jsonb_build_array(
    jsonb_build_object('firm_id', v_firm, 'box', 'F2', 'table', 'v2_startups',
      'fact', v_src || jsonb_build_object('startup_name', 'Acme Blog', 'website_url', 'https://blog.acme.test')),
    jsonb_build_object('firm_id', v_firm, 'box', 'F2', 'table', 'v2_startups',
      'fact', v_src || jsonb_build_object('startup_name', 'Revived', 'website_url', 'https://archived.test/new'))
  ), true);
  if v_reply->'results'->0->>'status' is distinct from 'Accepted'
     or v_reply->'results'->0 ? 'matched_startup_id'
     or v_reply->'results'->0->>'checker_queued' is distinct from 'accepted-item'
     or (v_reply->'results'->0->>'row_id')::bigint = v_existing
     or v_reply->'results'->1->>'status' is distinct from 'Accepted'
     or v_reply->'results'->1 ? 'matched_startup_id'
     or (v_reply->'results'->1->>'row_id')::bigint = v_archived then
    raise exception 'subdomain or archived domain: %', v_reply;
  end if;

  -- 6. Same name, new domain: insert. Dry run and a real call in this transaction agree.
  v_reply := public.v2_research_submit(v_key, jsonb_build_array(
    jsonb_build_object('firm_id', v_firm, 'box', 'F2', 'table', 'v2_startups', 'ref', 'same',
      'fact', v_src || jsonb_build_object('startup_name', 'Existing Acme', 'website_url', 'https://different-acme.test'))
  ), true);
  if v_reply->'results'->0->>'status' is distinct from 'Accepted'
     or v_reply->'results'->0 ? 'matched_startup_id'
     or v_reply->'results'->0->>'checker_queued' is distinct from 'accepted-item'
     or v_reply->>'dry_run' is distinct from 'true' then
    raise exception 'same name dry run: %', v_reply;
  end if;
  v_reply := public.v2_research_submit(v_key, jsonb_build_array(
    jsonb_build_object('firm_id', v_firm, 'box', 'F2', 'table', 'v2_startups', 'ref', 'same',
      'fact', v_src || jsonb_build_object('startup_name', 'Existing Acme', 'website_url', 'https://different-acme.test'))
  ), false);
  v_new_id := (v_reply->'results'->0->>'row_id')::bigint;
  if v_reply->>'dry_run' is distinct from 'false'
     or v_reply->'results'->0->>'status' is distinct from 'Accepted'
     or v_reply->'results'->0 ? 'matched_startup_id'
     or v_reply->'results'->0->>'checker_queued' is distinct from 'accepted-item' then
    raise exception 'same name insert: %', v_reply;
  end if;
  select startup_name, website_url, is_current into v_name, v_site, v_current
  from public.v2_startups where startup_id = v_new_id;
  if v_name is distinct from 'Existing Acme' or v_site is distinct from 'https://different-acme.test'
     or v_current is distinct from false
     or (select domain from public.v2_startups where startup_id = v_new_id) is distinct from 'different-acme.test' then
    raise exception 'same name row was not inserted hidden with that domain';
  end if;
  if (select count(*) from public.v2_checker_queue where row_id = v_new_id and kind = 'accepted-item' and table_name = 'v2_startups') <> 1 then
    raise exception 'same name insert was not queued for the Checker';
  end if;
  if (select startup_name from public.v2_startups where startup_id = v_existing) is distinct from 'Existing Acme' then
    raise exception 'same name insert changed the existing startup';
  end if;

  -- 7. Matched ref is used by a later v2_deals item. Dry run matches the real call.
  v_reply := public.v2_research_submit(v_key, jsonb_build_array(
    jsonb_build_object('firm_id', v_firm, 'box', 'F2', 'table', 'v2_startups', 'ref', 'acme',
      'fact', v_src || jsonb_build_object('startup_name', 'Submitted Acme', 'website_url', 'https://www.acme.test/team')),
    jsonb_build_object('firm_id', v_firm, 'box', 'F2', 'table', 'v2_deals',
      'fact', v_src || jsonb_build_object('startup_id', '@acme', 'round', 'Seed', 'deal_date', '2026-11-01'))
  ), true);
  v_item := v_reply->'results'->0;
  v_deal := v_reply->'results'->1;
  if v_item->>'status' is distinct from 'Accepted'
     or (v_item->>'matched_startup_id')::bigint is distinct from v_existing
     or v_item ? 'checker_queued'
     or position('Submitted Acme' in v_item->>'note') = 0
     or position('Existing Acme' in v_item->>'note') = 0
     or v_deal->>'status' is distinct from 'Accepted'
     or v_deal->>'table' is distinct from 'v2_deals'
     or v_deal->>'status' like 'Rejected:%' then
    raise exception 'dry-run ref batch: %', v_reply;
  end if;
  if (select count(*) from public.v2_deals where firm_id = v_firm) <> 0 then
    raise exception 'dry run kept a deal';
  end if;

  v_reply := public.v2_research_submit(v_key, jsonb_build_array(
    jsonb_build_object('firm_id', v_firm, 'box', 'F2', 'table', 'v2_startups', 'ref', 'acme',
      'fact', v_src || jsonb_build_object('startup_name', 'Submitted Acme', 'website_url', 'https://www.acme.test/team')),
    jsonb_build_object('firm_id', v_firm, 'box', 'F2', 'table', 'v2_deals',
      'fact', v_src || jsonb_build_object('startup_id', '@acme', 'round', 'Seed', 'deal_date', '2026-11-01'))
  ), false);
  v_item := v_reply->'results'->0;
  v_deal := v_reply->'results'->1;
  if v_item->>'status' is distinct from 'Accepted'
     or (v_item->>'matched_startup_id')::bigint is distinct from v_existing
     or v_deal->>'status' is distinct from 'Accepted' then
    raise exception 'ref batch: %', v_reply;
  end if;
  select startup_name, website_url, is_current into v_name, v_site, v_current
  from public.v2_startups where startup_id = v_existing;
  if v_name is distinct from 'Existing Acme' or v_site is distinct from 'https://www.acme.test/about' or v_current is distinct from true then
    raise exception 'match wrote the existing startup (name %, site %, current %)', v_name, v_site, v_current;
  end if;
  if exists (
    select 1 from public.v2_checker_queue q
    where q.submission_id = (v_item->>'submission_id')::bigint
  ) then
    raise exception 'match was queued for the Checker';
  end if;
  if not exists (
    select 1 from public.v2_change_log c
    where c.submission_id = (v_item->>'submission_id')::bigint
      and c.result = 'Accepted'
      and c.row_id = v_existing
      and c.old_value->>'startup_name' = 'Existing Acme'
      and c.new_value->>'startup_name' = 'Submitted Acme'
  ) then
    raise exception 'match was not logged with both names';
  end if;
  select startup_id, shown, is_current into v_deal_startup, v_shown, v_current
  from public.v2_deals where deal_id = (v_deal->>'row_id')::bigint;
  if v_deal_startup is distinct from v_existing or v_shown is distinct from false or v_current is distinct from false then
    raise exception 'deal did not use the matched startup (startup %, shown %, current %)', v_deal_startup, v_shown, v_current;
  end if;

  -- Website fill for a given startup_id stays on the old path.
  v_reply := public.v2_research_submit(v_key, jsonb_build_array(
    jsonb_build_object('firm_id', v_firm, 'box', 'F2', 'table', 'v2_startups',
      'fact', v_src || jsonb_build_object('startup_id', v_empty, 'website_url', 'https://needs-a-site.test'))
  ), true);
  if v_reply->'results'->0->>'status' is distinct from 'Held: empty startup website waits for the Checker'
     or v_reply->'results'->0->>'checker_queued' is distinct from 'changed-key-fact'
     or (v_reply->'results'->0->>'row_id')::bigint is distinct from v_empty
     or v_reply->'results'->0 ? 'matched_startup_id' then
    raise exception 'website fill changed: %', v_reply;
  end if;

  -- This website rejection does not count toward the freeze. A normal rejection still does.
  insert into public.v2_research_submissions (batch_id, firm_id, bot_key_id, target_box, payload, status, received_at)
  select nextval('public.v2_batch_seq'), v_firm, v_bk, 'F2', '{"seed":true}'::jsonb,
         'Rejected: ' || v_reason, now()
  from generate_series(1, 100);
  v_reply := public.v2_research_submit(v_key, jsonb_build_array(
    jsonb_build_object('firm_id', v_firm, 'box', 'F2', 'table', 'v2_startups',
      'fact', v_src || jsonb_build_object('startup_name', 'Still No Site'))
  ), true);
  if v_reply ? 'would_freeze' or v_reply ? 'key_frozen'
     or v_reply->'results'->0->>'status' is distinct from 'Rejected: ' || v_reason then
    raise exception 'website rejection counted toward the freeze: %', v_reply;
  end if;
  if (select frozen from public.v2_bot_keys where bot_key_id = v_bk) then
    raise exception 'website rejection froze the key';
  end if;
  delete from public.v2_research_submissions
  where bot_key_id = v_bk and status = 'Rejected: ' || v_reason;

  insert into public.v2_research_submissions (batch_id, firm_id, bot_key_id, target_box, payload, status, received_at)
  select nextval('public.v2_batch_seq'), v_firm, v_bk, 'F2', '{"seed":true}'::jsonb,
         'Rejected: no source link (source_url)', now()
  from generate_series(1, 99);
  v_reply := public.v2_research_submit(v_key, jsonb_build_array(
    jsonb_build_object('firm_id', v_firm, 'box', 'F2', 'table', 'v2_startups',
      'fact', jsonb_build_object('startup_name', 'Missing Source', 'website_url', 'https://missing-source.test'))
  ), true);
  if v_reply->>'would_freeze' is distinct from '100 rejections today for one firm'
     or v_reply ? 'key_frozen'
     or v_reply->'results'->0->>'status' is distinct from 'Rejected: no source link (source_url)' then
    raise exception 'normal rejections should still freeze on a dry run: %', v_reply;
  end if;
  delete from public.v2_research_submissions
  where bot_key_id = v_bk and status = 'Rejected: no source link (source_url)';

  -- 8. Unique-violation race. Off unless the session asked for it.
  if v_race then
    if to_regprocedure('dblink_connect(text,text)') is null then
      raise exception 'race case needs the dblink extension installed already';
    end if;
    perform dblink_connect('race', 'dbname=' || current_database());
    perform dblink_exec('race', 'delete from public.v2_startups where domain = ''v2-submit-race-test.invalid''');
    perform dblink_exec('race', 'delete from public.v2_research_submissions where bot_key_id in (select bot_key_id from public.v2_bot_keys where bot_name = ''v2-startup-race-plant'') or payload->>''race'' = ''v2-submit-race-test''');
    perform dblink_exec('race', 'delete from public.v2_bot_keys where bot_name = ''v2-startup-race-plant''');
    perform dblink_exec('race', 'delete from public.v2_firms where display_name = ''Race Plant Firm''');
    select firm_id into v_race_firm from dblink('race',
      'insert into public.v2_firms (display_name, firm_status) values (''Race Plant Firm'', ''Active'') returning firm_id')
      as t(firm_id bigint);
    select bot_key_id into v_race_key from dblink('race',
      'insert into public.v2_bot_keys (bot_name, key_hash) values (''v2-startup-race-plant'', ''race-hash'') returning bot_key_id')
      as t(bot_key_id bigint);
    select submission_id into v_race_sub from dblink('race', format(
      'insert into public.v2_research_submissions (batch_id, firm_id, bot_key_id, target_box, payload, status) values (nextval(''public.v2_batch_seq''), %s, %s, ''F2'', ''{"race":"v2-submit-race-test"}''::jsonb, ''Accepted'') returning submission_id',
      v_race_firm, v_race_key)) as t(submission_id bigint);
    perform set_config('v2.race_submission_id', v_race_sub::text, true);
    if to_regclass('pg_trigger') is not null and not exists (
      select 1 from pg_trigger where tgname = 'v2_startup_race_plant' and not tgisinternal
    ) then
      raise exception 'race trigger is missing; the setup block did not commit it';
    end if;

    v_reply := public.v2_research_submit(v_key, jsonb_build_array(
      jsonb_build_object('firm_id', v_firm, 'box', 'F2', 'table', 'v2_startups', 'ref', 'race',
        'fact', v_src || jsonb_build_object('startup_name', 'Race Submit', 'website_url', 'https://v2-submit-race-test.invalid/path'))
    ), true);
    select startup_id into v_plant from public.v2_startups
    where domain = 'v2-submit-race-test.invalid' and not archived;
    if v_plant is null
       or v_reply->'results'->0->>'status' is distinct from 'Accepted'
       or (v_reply->'results'->0->>'matched_startup_id')::bigint is distinct from v_plant
       or v_reply->'results'->0 ? 'checker_queued'
       or (select count(*) from public.v2_startups where domain = 'v2-submit-race-test.invalid' and not archived) <> 1 then
      raise exception 'unique-violation race: plant %, reply %', v_plant, v_reply;
    end if;

    perform dblink_exec('race', 'delete from public.v2_startups where domain = ''v2-submit-race-test.invalid''');
    perform dblink_exec('race', format('delete from public.v2_research_submissions where submission_id = %s', v_race_sub));
    perform dblink_exec('race', format('delete from public.v2_bot_keys where bot_key_id = %s', v_race_key));
    perform dblink_exec('race', format('delete from public.v2_firms where firm_id = %s', v_race_firm));
    perform dblink_disconnect('race');
    raise notice 'unique-violation race case passed';
  else
    raise notice 'unique-violation race case skipped (set v2.run_startup_race_test = on to run it)';
  end if;

  raise exception 'v2_startup_website_identity_ok';
exception when others then
  if to_regprocedure('dblink_get_connections()') is not null then
   if coalesce(dblink_get_connections() @> array['race']::text[], false) then
    begin
      perform dblink_exec('race', 'drop trigger if exists v2_startup_race_plant on public.v2_startups');
      perform dblink_exec('race', 'drop function if exists public.v2_startup_race_plant()');
      perform dblink_exec('race', 'delete from public.v2_startups where domain = ''v2-submit-race-test.invalid''');
      if v_race_sub is not null then
        perform dblink_exec('race', format('delete from public.v2_research_submissions where submission_id = %s', v_race_sub));
      end if;
      if v_race_key is not null then
        perform dblink_exec('race', format('delete from public.v2_bot_keys where bot_key_id = %s', v_race_key));
      end if;
      if v_race_firm is not null then
        perform dblink_exec('race', format('delete from public.v2_firms where firm_id = %s', v_race_firm));
      end if;
      perform dblink_disconnect('race');
    exception when others then
      null;
    end;
   end if;
  end if;
  if SQLERRM = 'v2_startup_website_identity_ok' then
    raise notice 'v2_startup_website_identity: all dry-run cases passed';
  else
    raise;
  end if;
end
$test$;

-- Drop the committed race trigger after the test transaction has released its locks.
do $race_cleanup$
begin
  if to_regprocedure('dblink_connect(text,text)') is null then
    return;
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'v2_startup_race_plant' and not tgisinternal)
     and to_regprocedure('public.v2_startup_race_plant()') is null then
    return;
  end if;
  perform dblink_connect('race_cleanup', 'dbname=' || current_database());
  perform dblink_exec('race_cleanup', 'drop trigger if exists v2_startup_race_plant on public.v2_startups');
  perform dblink_exec('race_cleanup', 'drop function if exists public.v2_startup_race_plant()');
  perform dblink_exec('race_cleanup', 'delete from public.v2_startups where domain = ''v2-submit-race-test.invalid'' or submission_id in (select submission_id from public.v2_research_submissions where bot_key_id in (select bot_key_id from public.v2_bot_keys where bot_name = ''v2-startup-race-plant''))');
  perform dblink_exec('race_cleanup', 'delete from public.v2_research_submissions where payload->>''race'' = ''v2-submit-race-test'' or bot_key_id in (select bot_key_id from public.v2_bot_keys where bot_name = ''v2-startup-race-plant'')');
  perform dblink_exec('race_cleanup', 'delete from public.v2_bot_keys where bot_name = ''v2-startup-race-plant''');
  perform dblink_exec('race_cleanup', 'delete from public.v2_firms where display_name = ''Race Plant Firm''');
  perform dblink_disconnect('race_cleanup');
end
$race_cleanup$;
