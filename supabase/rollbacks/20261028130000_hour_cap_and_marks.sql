-- Puts the attack line back on door_attack_at (three times the hourly limit at the moment this runs).
-- Restores the Checker writers from before the three item columns.
-- Drops checked_on, checked_by, and source_level. Does not drop searched_at or check_mark.
-- Does not drop marks_fold_backup. Does not delete page rows.

insert into bots.ingest_settings(key, value)
select 'door_attack_at', (coalesce((select value::int from bots.ingest_settings where key = 'door_hour_cap'), 100) * 3)::text
where not exists (select 1 from bots.ingest_settings where key = 'door_attack_at');

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
  attack := coalesce((select value::int from ingest_settings where key = 'door_attack_at'), 300);
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

create or replace function public._checker_write(p_firm uuid, p_section text, p_f jsonb, p_url text, p_level smallint, p_check int)
returns uuid
language plpgsql security definer set search_path = public as $$
declare rid uuid := gen_random_uuid(); key text; n int := p_check;
begin
  key := p_section || '|' || coalesce(nullif(p_url, ''), left(p_f::text, 200));
  if p_section = 'press' then
    insert into press_items(id, publisher, domain, url, published_label, headline, snippet, data_status, retrieved_at, source_system)
    values (rid, coalesce(p_f->>'outlet', public.source_label(public._dom(p_url), p_url)), public._dom(p_url), p_url,
            p_f->>'date', left(coalesce(p_f->>'headline', ''), 400), left(p_f->>'snippet', 600), 'real', now(), 'checker');
    insert into press_item_firms(press_item_id, firm_id, sort_order, check_mark)
    values (rid, p_firm, 900, 'checked_correct');
  elsif p_section = 'timeline' then
    insert into timeline_events(id, firm_id, date_label, kind, body, sort_order, source_url, check_mark)
    values (rid, p_firm, p_f->>'date', 'Reported', left(coalesce(p_f->>'event', ''), 300), 900, p_url, 'checked_correct');
  elsif p_section = 'people' then
    insert into firm_people_roles(id, firm_id, kind, person_name, role, sort_order)
    values (rid, p_firm, coalesce(p_f->>'kind', 'officer'), left(p_f->>'name', 120), left(coalesce(p_f->>'role', ''), 300), 900);
  elsif p_section in ('overview', 'funds', 'lps') then
    insert into firm_profile_facts(id, firm_id, section, label, value, sort_order, origin)
    values (rid, p_firm, p_section,
            case p_section when 'overview' then p_f->>'label' when 'lps' then p_f->>'name' else 'Funds' end,
            left(case p_section when 'overview' then p_f->>'value' when 'lps' then p_f->>'name' else coalesce(p_f->>'name', '') end, 400),
            900, 'checker');
  elsif p_section = 'legal' then
    insert into firm_legal_items(id, firm_id, grp, title, year_label, status_label, sort_order)
    values (rid, p_firm, 'context', left(coalesce(p_f->>'title', ''), 300), substring(p_f->>'date' from '^(\d{4})'), p_f->>'status', 900);
  elsif p_section = 'founders' then
    insert into reviews(id, firm_id, body, first_hand, verification_status, moderation_status, anonymous, author_name, source_urls,
                        review_type, is_public, source_system, dedupe_key)
    values (rid, p_firm, left(coalesce(p_f->>'quote', ''), 2000), false, 'unverified', 'approved', false,
            left(p_f->>'who', 200), array[p_url], 'founder', true, 'checker', 'url:' || left(p_url, 400));
  elsif n is not null then
    insert into vc_source_facts(firm_id, fact_type, section, value, source_url, source_label, retrieved_at, data_status, source_system, external_id)
    values (p_firm,
            case when n in (1, 2, 10) then 'sanctions_check' when n in (4, 5) then 'regulatory_record' when n = 8 then 'fund_fact' else 'legal_matter' end,
            'checks',
            jsonb_build_object('field', case n when 1 then 'sanctions' when 2 then 'terrorism_lists' when 3 then 'export_restrictions'
              when 4 then 'regulatory_action' when 5 then 'aml_penalties' when 7 then 'courts_worldwide' when 8 then 'registration_status'
              when 9 then 'people_screen' when 10 then 'pep' else 'legal_matter' end, 'value', left(p_f::text, 500)),
            p_url, 'Checker', now(), 'real', 'checker', 'checker:' || p_firm::text || ':' || n::text || ':' || md5(coalesce(p_url, '') || p_f::text));
    rid := gen_random_uuid();
  else
    return null;
  end if;
  insert into checker_marks(firm_id, kind, item_key, checked_by, source_level, url)
  values (p_firm, coalesce(p_section, 'check'), key, 'Checker', p_level, p_url)
  on conflict (firm_id, kind, item_key) do nothing;
  return rid;
end $$;

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
    perform public._checker_note(p_firm, p_section, p_origin, raw_old, raw_new, 'merged: new value won, old value kept as a note');
    insert into checker_marks(firm_id, kind, item_key, checked_by, source_level, url)
    values (p_firm, p_section, p_section || '|' || coalesce(nullif(p_url, ''), left(p_f::text, 200)), 'Checker', p_level, p_url)
    on conflict (firm_id, kind, item_key) do update set source_level = least(checker_marks.source_level, excluded.source_level), checked_on = now();
    outcome := 'merged'; reason := 'new value won'; return next; return;
  end if;
  perform public._checker_note(p_firm, p_section, p_origin, raw_new, raw_old, 'merged: page value won, new value kept as a note');
  outcome := 'note'; reason := 'page value won'; return next;
end $$;

drop function if exists public._checker_stamp(text, uuid, uuid, smallint);
drop function if exists public.fold_legacy_marks();
drop function if exists public._fold_source_level(text, text, uuid);

do $$
declare t text;
begin
  foreach t in array array[
    'press_item_firms', 'timeline_events', 'firm_check_rows', 'firm_people_roles',
    'firm_profile_facts', 'firm_legal_items', 'reviews', 'vc_source_facts'
  ]
  loop
    execute format('alter table public.%I drop constraint if exists %I', t, t || '_source_level_chk');
    execute format('alter table public.%I drop column if exists checked_on, drop column if exists checked_by, drop column if exists source_level', t);
  end loop;
end $$;
