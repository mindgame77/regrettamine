-- One hourly limit. door_hour_cap starts at 100. The attack line is three times that
-- number. door_attack_at is no longer read, and the row is removed so a second
-- knob cannot drift away from the limit.
-- Three marks on each item the Checker writes, lab firms only for the fold.
-- fact_sources stays a link from a URL to an item. Press and the 10 checks do
-- not keep the source pill there, and one item can have several links, so the
-- marks sit on the item row. searched_at and check_mark stay.
-- The page does not read the new columns. The mockup is not shipped.
-- Rollback: supabase/rollbacks/20261028130000_hour_cap_and_marks.sql

create or replace function public._door_admit(p_bot text, p_id text, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = bots, public as $$
declare known text; cap int; attack int; dkey text; n int; already boolean;
begin
  perform pg_advisory_xact_lock(hashtext('door:' || coalesce(p_bot, '')));
  known := public._door_known(p_bot);
  if known = 'unknown' then
    return jsonb_build_object('ok', false, 'error', 'unknown bot', 'status', 'rejected');
  end if;
  if known = 'off' then
    return jsonb_build_object('ok', false, 'error', 'bot is off', 'status', 'off');
  end if;
  dkey := public._door_key(p_id, p_payload);
  if exists (select 1 from research_submissions s where s.door_key = dkey) then
    return jsonb_build_object('ok', true, 'status', 'duplicate', 'dropped', true, 'door_key', dkey);
  end if;
  cap := coalesce((select value::int from ingest_settings where key = 'door_hour_cap'), 100);
  if cap is null or cap < 1 then cap := 100; end if;
  attack := cap * 3;
  select count(distinct s.registry_id) into n from research_submissions s
   where s.bot_id = p_bot and s.received_at > now() - interval '1 hour'
     and coalesce(s.door_status, 'ready') in ('ready', 'waiting', 'frozen', 'checked');
  already := exists (select 1 from research_submissions s
   where s.bot_id = p_bot and s.registry_id = p_id and s.received_at > now() - interval '1 hour'
     and coalesce(s.door_status, 'ready') in ('ready', 'waiting', 'frozen', 'checked'));
  if not already then n := n + 1; end if;
  if not already and n > attack then
    update ingest_keys set active = false where name = p_bot or bot_id = p_bot;
    update research_submissions set door_status = 'frozen'
     where bot_id = p_bot and door_status = 'waiting';
    perform public._door_alert(p_bot, 'attack',
      'More than ' || attack || ' distinct firms in an hour. Key blocked. Waiting items frozen. Only Alex can unblock.');
    return jsonb_build_object('ok', false, 'error', 'blocked', 'status', 'blocked');
  end if;
  if already or n <= cap then
    return jsonb_build_object('ok', true, 'status', 'ready', 'ready_at', now(), 'door_key', dkey, 'door_status', 'ready');
  end if;
  return jsonb_build_object('ok', true, 'status', 'waiting',
    'ready_at', date_trunc('hour', now()) + interval '1 hour', 'door_key', dkey, 'door_status', 'waiting');
end $$;
revoke all on function public._door_admit(text, text, jsonb) from public, anon, authenticated;

delete from bots.ingest_settings where key = 'door_attack_at';

do $$
declare t text;
begin
  foreach t in array array[
    'press_item_firms', 'timeline_events', 'firm_check_rows', 'firm_people_roles',
    'firm_profile_facts', 'firm_legal_items', 'reviews', 'vc_source_facts'
  ]
  loop
    execute format('alter table public.%I add column if not exists checked_on timestamptz', t);
    execute format('alter table public.%I add column if not exists checked_by text', t);
    execute format('alter table public.%I add column if not exists source_level smallint', t);
    execute format('alter table public.%I drop constraint if exists %I', t, t || '_source_level_chk');
    execute format(
      'alter table public.%I add constraint %I check (source_level is null or source_level between 1 and 4)',
      t, t || '_source_level_chk');
    execute format($c$comment on column public.%I.checked_on is 'Date the Checker checked this item. Copied from an older date on lab firms. The page does not read this yet.'$c$, t);
    execute format($c$comment on column public.%I.checked_by is 'Who checked this item. The Checker writes Checker. A folded older row stays empty.'$c$, t);
    execute format($c$comment on column public.%I.source_level is '1 official register, 2 firm site or a page part that may be shown, 3 elsewhere online, 4 nothing found.'$c$, t);
  end loop;
end $$;

create table if not exists public.marks_fold_backup (
  id bigserial primary key,
  backed_up_at timestamptz not null default now(),
  table_name text not null,
  firm_id uuid not null,
  item_key text not null,
  old_values jsonb not null,
  unique (table_name, item_key)
);
alter table public.marks_fold_backup enable row level security;
revoke all on public.marks_fold_backup from public, anon, authenticated;
comment on table public.marks_fold_backup is
  'Copy of lab searched_at and news check_mark values taken before they were folded into checked_on. The old columns stay.';

create or replace function public._fold_source_level(p_mark text, p_url text, p_firm uuid)
returns smallint
language sql stable security definer set search_path = public as $$
  select case
    when p_mark = 'checked_correct' and public._known_outlet(p_url) then 2::smallint
    else public._source_level(p_url, p_firm)
  end;
$$;
revoke all on function public._fold_source_level(text, text, uuid) from public, anon, authenticated;

create or replace function public.fold_legacy_marks() returns jsonb
language plpgsql security definer set search_path = public as $$
declare n_check int := 0; n_press int := 0; n_time int := 0;
begin
  insert into marks_fold_backup(table_name, firm_id, item_key, old_values)
  select 'firm_check_rows', r.firm_id, r.firm_id::text || '|' || r.n::text,
         jsonb_build_object('searched_at', r.searched_at)
    from firm_check_rows r
   where public._lab_firm(r.firm_id) and r.searched_at is not null
  on conflict (table_name, item_key) do nothing;

  insert into marks_fold_backup(table_name, firm_id, item_key, old_values)
  select 'press_item_firms', pf.firm_id, pf.press_item_id::text || '|' || pf.firm_id::text,
         jsonb_build_object('check_mark', pf.check_mark, 'last_checked_at', pf.last_checked_at,
                            'checked_source', pf.checked_source, 'url', p.url)
    from press_item_firms pf
    join press_items p on p.id = pf.press_item_id
   where public._lab_firm(pf.firm_id)
     and pf.check_mark in ('checked_correct', 'checked_wrong')
  on conflict (table_name, item_key) do nothing;

  insert into marks_fold_backup(table_name, firm_id, item_key, old_values)
  select 'timeline_events', t.firm_id, t.id::text,
         jsonb_build_object('check_mark', t.check_mark, 'last_checked_at', t.last_checked_at,
                            'checked_source', t.checked_source, 'source_url', t.source_url)
    from timeline_events t
   where public._lab_firm(t.firm_id)
     and t.check_mark in ('checked_correct', 'checked_wrong')
  on conflict (table_name, item_key) do nothing;

  update firm_check_rows r
     set checked_on = r.searched_at
   where public._lab_firm(r.firm_id)
     and r.searched_at is not null
     and r.checked_on is null
     and r.checked_by is null;
  get diagnostics n_check = row_count;

  update press_item_firms pf
     set checked_on = coalesce(pf.checked_on, pf.last_checked_at),
         source_level = coalesce(pf.source_level, public._fold_source_level(pf.check_mark, p.url, pf.firm_id))
    from press_items p
   where p.id = pf.press_item_id
     and public._lab_firm(pf.firm_id)
     and pf.check_mark in ('checked_correct', 'checked_wrong')
     and pf.checked_by is null
     and (
       (pf.checked_on is null and pf.last_checked_at is not null)
       or (pf.source_level is null and public._fold_source_level(pf.check_mark, p.url, pf.firm_id) is not null)
     );
  get diagnostics n_press = row_count;

  update timeline_events t
     set checked_on = coalesce(t.checked_on, t.last_checked_at),
         source_level = coalesce(t.source_level, public._fold_source_level(t.check_mark, t.source_url, t.firm_id))
   where public._lab_firm(t.firm_id)
     and t.check_mark in ('checked_correct', 'checked_wrong')
     and t.checked_by is null
     and (
       (t.checked_on is null and t.last_checked_at is not null)
       or (t.source_level is null and public._fold_source_level(t.check_mark, t.source_url, t.firm_id) is not null)
     );
  get diagnostics n_time = row_count;

  return jsonb_build_object('checks', n_check, 'press', n_press, 'timeline', n_time);
end $$;
revoke all on function public.fold_legacy_marks() from public, anon, authenticated;

create or replace function public._checker_stamp(p_section text, p_firm uuid, p_id uuid, p_level smallint)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_id is null or not public._lab_firm(p_firm) then return; end if;
  if p_section = 'press' then
    update press_item_firms set checked_on = now(), checked_by = 'Checker', source_level = p_level
     where press_item_id = p_id and firm_id = p_firm;
  elsif p_section = 'timeline' then
    update timeline_events set checked_on = now(), checked_by = 'Checker', source_level = p_level where id = p_id;
  elsif p_section = 'people' then
    update firm_people_roles set checked_on = now(), checked_by = 'Checker', source_level = p_level where id = p_id;
  elsif p_section in ('overview', 'funds', 'lps') then
    update firm_profile_facts set checked_on = now(), checked_by = 'Checker', source_level = p_level where id = p_id;
  elsif p_section = 'legal' then
    update firm_legal_items set checked_on = now(), checked_by = 'Checker', source_level = p_level where id = p_id;
  elsif p_section = 'founders' then
    update reviews set checked_on = now(), checked_by = 'Checker', source_level = p_level where id = p_id;
  end if;
end $$;
revoke all on function public._checker_stamp(text, uuid, uuid, smallint) from public, anon, authenticated;

create or replace function public._checker_write(p_firm uuid, p_section text, p_f jsonb, p_url text, p_level smallint, p_check int)
returns uuid
language plpgsql security definer set search_path = public as $$
declare rid uuid := gen_random_uuid(); key text; n int := p_check; lab boolean := public._lab_firm(p_firm);
begin
  key := p_section || '|' || coalesce(nullif(p_url, ''), left(p_f::text, 200));
  if p_section = 'press' then
    insert into press_items(id, publisher, domain, url, published_label, headline, snippet, data_status, retrieved_at, source_system)
    values (rid, coalesce(p_f->>'outlet', public.source_label(public._dom(p_url), p_url)), public._dom(p_url), p_url,
            p_f->>'date', left(coalesce(p_f->>'headline', ''), 400), left(p_f->>'snippet', 600), 'real', now(), 'checker');
    insert into press_item_firms(press_item_id, firm_id, sort_order, check_mark, checked_on, checked_by, source_level)
    values (rid, p_firm, 900, 'checked_correct', case when lab then now() end, case when lab then 'Checker' end, case when lab then p_level end);
  elsif p_section = 'timeline' then
    insert into timeline_events(id, firm_id, date_label, kind, body, sort_order, source_url, check_mark, checked_on, checked_by, source_level)
    values (rid, p_firm, p_f->>'date', 'Reported', left(coalesce(p_f->>'event', ''), 300), 900, p_url, 'checked_correct',
            case when lab then now() end, case when lab then 'Checker' end, case when lab then p_level end);
  elsif p_section = 'people' then
    insert into firm_people_roles(id, firm_id, kind, person_name, role, sort_order, checked_on, checked_by, source_level)
    values (rid, p_firm, coalesce(p_f->>'kind', 'officer'), left(p_f->>'name', 120), left(coalesce(p_f->>'role', ''), 300), 900,
            case when lab then now() end, case when lab then 'Checker' end, case when lab then p_level end);
  elsif p_section in ('overview', 'funds', 'lps') then
    insert into firm_profile_facts(id, firm_id, section, label, value, sort_order, origin, checked_on, checked_by, source_level)
    values (rid, p_firm, p_section,
            case p_section when 'overview' then p_f->>'label' when 'lps' then p_f->>'name' else 'Funds' end,
            left(case p_section when 'overview' then p_f->>'value' when 'lps' then p_f->>'name' else coalesce(p_f->>'name', '') end, 400),
            900, 'checker', case when lab then now() end, case when lab then 'Checker' end, case when lab then p_level end);
  elsif p_section = 'legal' then
    insert into firm_legal_items(id, firm_id, grp, title, year_label, status_label, sort_order, checked_on, checked_by, source_level)
    values (rid, p_firm, 'context', left(coalesce(p_f->>'title', ''), 300), substring(p_f->>'date' from '^(\d{4})'), p_f->>'status', 900,
            case when lab then now() end, case when lab then 'Checker' end, case when lab then p_level end);
  elsif p_section = 'founders' then
    insert into reviews(id, firm_id, body, first_hand, verification_status, moderation_status, anonymous, author_name, source_urls,
                        review_type, is_public, source_system, dedupe_key, checked_on, checked_by, source_level)
    values (rid, p_firm, left(coalesce(p_f->>'quote', ''), 2000), false, 'unverified', 'approved', false,
            left(p_f->>'who', 200), array[p_url], 'founder', true, 'checker', 'url:' || left(p_url, 400),
            case when lab then now() end, case when lab then 'Checker' end, case when lab then p_level end);
  elsif n is not null then
    insert into vc_source_facts(firm_id, fact_type, section, value, source_url, source_label, retrieved_at, data_status, source_system, external_id,
                                checked_on, checked_by, source_level)
    values (p_firm,
            case when n in (1, 2, 10) then 'sanctions_check' when n in (4, 5) then 'regulatory_record' when n = 8 then 'fund_fact' else 'legal_matter' end,
            'checks',
            jsonb_build_object('field', case n when 1 then 'sanctions' when 2 then 'terrorism_lists' when 3 then 'export_restrictions'
              when 4 then 'regulatory_action' when 5 then 'aml_penalties' when 7 then 'courts_worldwide' when 8 then 'registration_status'
              when 9 then 'people_screen' when 10 then 'pep' else 'legal_matter' end, 'value', left(p_f::text, 500)),
            p_url, 'Checker', now(), 'real', 'checker', 'checker:' || p_firm::text || ':' || n::text || ':' || md5(coalesce(p_url, '') || p_f::text),
            case when lab then now() end, case when lab then 'Checker' end, case when lab then p_level end);
    rid := gen_random_uuid();
  else
    return null;
  end if;
  insert into checker_marks(firm_id, kind, item_key, checked_by, source_level, url)
  values (p_firm, coalesce(p_section, 'check'), key, 'Checker', p_level, p_url)
  on conflict (firm_id, kind, item_key) do nothing;
  return rid;
end $$;
revoke all on function public._checker_write(uuid, text, jsonb, text, smallint, int) from public, anon, authenticated;

create or replace function public._checker_place(p_firm uuid, p_section text, p_f jsonb, p_url text, p_level smallint, p_check int, p_origin bigint)
returns table(outcome text, reason text)
language plpgsql security definer set search_path = bots, public as $$
declare kept uuid; old_text text; new_text text; old_level smallint; old_date text; new_date text;
  new_wins boolean; raw_new text; raw_old text;
begin
  new_text := public._checker_item_text(p_section, p_f);
  new_date := nullif(p_f->>'date', '');
  raw_new := coalesce(p_f->>'headline', p_f->>'event', p_f->>'role', p_f->>'value', p_f->>'name', p_f->>'title', p_f->>'quote', '');
  if p_section = 'press' then
    select p.id, public._norm_txt(p.headline), p.published_label, p.headline
      into kept, old_text, old_date, raw_old
      from press_items p join press_item_firms pf on pf.press_item_id = p.id
     where pf.firm_id = p_firm and public._checker_url_key(p.url) = public._checker_url_key(p_url)
     order by coalesce(pf.hidden, false), p.id limit 1;
  elsif p_section = 'people' then
    select r.id, public._norm_txt(r.role), null::text, r.role into kept, old_text, old_date, raw_old
      from firm_people_roles r
     where r.firm_id = p_firm and r.kind = coalesce(p_f->>'kind', 'officer')
       and r.stable_key = public._person_key(p_f->>'name')
     order by coalesce(r.hidden, false), r.id limit 1;
  elsif p_section = 'overview' then
    select f.id, public._norm_txt(f.value), null::text, f.value into kept, old_text, old_date, raw_old
      from firm_profile_facts f
     where f.firm_id = p_firm and f.section = 'overview'
       and public._norm_txt(coalesce(f.label, f.hero_label)) = public._norm_txt(p_f->>'label')
     order by coalesce(f.hidden, false), f.id limit 1;
  elsif p_section = 'legal' then
    select i.id, public._norm_txt(i.title), i.year_label, i.title into kept, old_text, old_date, raw_old
      from firm_legal_items i
     where i.firm_id = p_firm and i.stable_key = public._legal_key(p_f->>'title')
     order by coalesce(i.hidden, false), i.id limit 1;
  elsif p_section = 'timeline' then
    select t.id, public._norm_txt(t.body), t.date_label, t.body into kept, old_text, old_date, raw_old
      from timeline_events t
     where t.firm_id = p_firm and (
       public._checker_url_key(t.source_url) = public._checker_url_key(p_url)
       or t.stable_key = public._timeline_key(p_f->>'date', p_f->>'event'))
     order by coalesce(t.hidden, false), t.id limit 1;
  elsif p_section = 'founders' then
    select r.id, public._norm_txt(r.body), null::text, r.body into kept, old_text, old_date, raw_old
      from reviews r
     where r.firm_id = p_firm and p_url = any(coalesce(r.source_urls, '{}'))
     order by r.id limit 1;
  elsif p_section in ('funds', 'lps') then
    select f.id, public._norm_txt(f.value), null::text, f.value into kept, old_text, old_date, raw_old
      from firm_profile_facts f
     where f.firm_id = p_firm and f.section = p_section
       and (public._norm_txt(coalesce(f.label, f.hero_label, f.value)) = public._norm_txt(coalesce(p_f->>'name', p_f->>'label'))
            or (p_section = 'funds' and f.stable_key = public._fund_key(coalesce(p_f->>'name', ''))))
     order by coalesce(f.hidden, false), f.id limit 1;
  end if;
  select m.source_level into old_level from checker_marks m
   where m.firm_id = p_firm and m.kind = p_section and (m.url = p_url or m.item_key = p_section || '|' || coalesce(nullif(p_url, ''), left(p_f::text, 200)))
   order by m.checked_on desc limit 1;
  if kept is null then
    perform public._checker_write(p_firm, p_section, p_f, p_url, p_level, p_check);
    outcome := 'published'; reason := null; return next; return;
  end if;
  if old_text is not distinct from new_text then
    perform public._checker_keep_one_exact(p_firm);
    outcome := 'skipped'; reason := 'exact duplicate, kept one'; return next; return;
  end if;
  old_level := coalesce(old_level, 4);
  if p_level < old_level then new_wins := true;
  elsif p_level > old_level then new_wins := false;
  elsif new_date is not null and old_date is not null and new_date > old_date then new_wins := true;
  elsif new_date is not null and old_date is not null and new_date < old_date then new_wins := false;
  elsif length(raw_new) > length(coalesce(raw_old, '')) then new_wins := true;
  elsif length(raw_new) < length(coalesce(raw_old, '')) then new_wins := false;
  else
    perform public._checker_note(p_firm, p_section, p_origin, raw_new, raw_old, 'undecided: same level, date, and length');
    outcome := 'note'; reason := 'undecided, kept the row already on the page'; return next; return;
  end if;
  if new_wins then
    if p_section = 'press' then
      update press_items set headline = left(coalesce(p_f->>'headline', ''), 400), snippet = left(p_f->>'snippet', 600),
             published_label = coalesce(new_date, published_label) where id = kept;
    elsif p_section = 'people' then
      update firm_people_roles set role = left(coalesce(p_f->>'role', ''), 300) where id = kept;
    elsif p_section = 'overview' then
      update firm_profile_facts set value = left(coalesce(p_f->>'value', ''), 400) where id = kept;
    elsif p_section = 'legal' then
      update firm_legal_items set title = left(coalesce(p_f->>'title', ''), 300) where id = kept;
    elsif p_section = 'timeline' then
      update timeline_events set body = left(coalesce(p_f->>'event', ''), 300), date_label = coalesce(new_date, date_label) where id = kept;
    elsif p_section = 'founders' then
      update reviews set body = left(coalesce(p_f->>'quote', ''), 2000) where id = kept;
    elsif p_section in ('funds', 'lps') then
      update firm_profile_facts set value = left(coalesce(p_f->>'name', p_f->>'value', ''), 400) where id = kept;
    end if;
    perform public._checker_stamp(p_section, p_firm, kept, p_level);
    perform public._checker_note(p_firm, p_section, p_origin, raw_old, raw_new, 'merged: new value won, old value kept as a note');
    insert into checker_marks(firm_id, kind, item_key, checked_by, source_level, url)
    values (p_firm, p_section, p_section || '|' || coalesce(nullif(p_url, ''), left(p_f::text, 200)), 'Checker', p_level, p_url)
    on conflict (firm_id, kind, item_key) do update set source_level = least(checker_marks.source_level, excluded.source_level), checked_on = now();
    outcome := 'merged'; reason := 'new value won'; return next; return;
  end if;
  perform public._checker_note(p_firm, p_section, p_origin, raw_new, raw_old, 'merged: page value won, new value kept as a note');
  outcome := 'note'; reason := 'page value won'; return next;
end $$;
revoke all on function public._checker_place(uuid, text, jsonb, text, smallint, int, bigint) from public, anon, authenticated;

select public.fold_legacy_marks();
