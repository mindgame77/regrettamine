-- Lab firms only: the Enricher no longer writes the page, and the Checker does.
-- checker_publish is true. _lab_firm still limits that to the 10 lab slugs (or lab_firm_slugs).
-- A new row in bots.research_submissions runs the Checker in the same insert. No cron, no manual ping.
-- Exact copies: keep one, delete the extra. A different value follows the merge rule
-- (higher source level, then newer date, then the longer text). The loser is a note.
-- Other firms still publish through the Enricher. Rollback: supabase/rollbacks/20261028100000_checker_on_lab.sql

insert into bots.ingest_settings(key, value) values ('checker_publish', 'true')
on conflict (key) do update set value = 'true';

create or replace function public._checker_url_key(p_url text) returns text
language sql immutable as $$
  select nullif(regexp_replace(regexp_replace(regexp_replace(
    lower(btrim(coalesce(p_url, ''))), '^https?://(www\.)?', '', 'i'), '[?#].*$', ''), '/+$', ''), '');
$$;

create or replace function public._checker_item_text(p_section text, p_f jsonb) returns text
language sql immutable as $$
  select public._norm_txt(case p_section
    when 'press' then p_f->>'headline'
    when 'timeline' then p_f->>'event'
    when 'people' then p_f->>'role'
    when 'overview' then p_f->>'value'
    when 'funds' then p_f->>'name'
    when 'lps' then p_f->>'name'
    when 'legal' then p_f->>'title'
    when 'founders' then p_f->>'quote'
    else coalesce(p_f->>'value', p_f->>'headline', p_f->>'name', p_f->>'title', left(p_f::text, 300)) end);
$$;

create or replace function public._checker_note(p_firm uuid, p_section text, p_origin bigint, p_loser text, p_winner text, p_why text)
returns void language plpgsql security definer set search_path = bots, public as $$
begin
  insert into publish_checks(origin, origin_id, bot_id, firm_id, section, kind, item, outcome, reason)
  values ('submission', p_origin, 'checker', p_firm, p_section, 'merge',
          jsonb_build_object('loser', left(coalesce(p_loser, ''), 500), 'winner', left(coalesce(p_winner, ''), 500)),
          'note', left(p_why, 500));
end $$;
revoke all on function public._checker_note(uuid, text, bigint, text, text, text) from public, anon, authenticated;

-- Drop extra rows that are the same item and the same text. Different text is left for the merge rule.
create or replace function public._checker_keep_one_exact(p_firm uuid) returns int
language plpgsql security definer set search_path = bots, public as $$
declare n int := 0; d int; ids uuid[];
begin
  if not public._lab_firm(p_firm) then return 0; end if;
  with ranked as (
    select pf.press_item_id,
           row_number() over (
             partition by public._checker_url_key(p.url), public._norm_txt(p.headline)
             order by coalesce(pf.hidden, false), (pf.check_mark = 'checked_correct') desc, p.id) rn
      from press_item_firms pf
      join press_items p on p.id = pf.press_item_id
     where pf.firm_id = p_firm and public._checker_url_key(p.url) is not null
  )
  select array_agg(press_item_id) into ids from ranked where rn > 1;
  if ids is not null then
    delete from press_item_firms where firm_id = p_firm and press_item_id = any(ids);
    get diagnostics d = row_count; n := n + d;
    delete from press_items p where p.id = any(ids)
      and not exists (select 1 from press_item_firms pf where pf.press_item_id = p.id);
  end if;
  with ranked as (
    select id, row_number() over (
             partition by kind, stable_key, public._norm_txt(role)
             order by coalesce(hidden, false), id) rn
      from firm_people_roles
     where firm_id = p_firm and stable_key is not null
  )
  delete from firm_people_roles r using ranked x where r.id = x.id and x.rn > 1;
  get diagnostics d = row_count; n := n + d;
  with ranked as (
    select id, row_number() over (
             partition by stable_key, public._norm_txt(title)
             order by coalesce(hidden, false), id) rn
      from firm_legal_items
     where firm_id = p_firm and stable_key is not null
  )
  delete from firm_legal_items r using ranked x where r.id = x.id and x.rn > 1;
  get diagnostics d = row_count; n := n + d;
  with ranked as (
    select id, row_number() over (
             partition by stable_key, public._norm_txt(body)
             order by coalesce(hidden, false), id) rn
      from timeline_events
     where firm_id = p_firm and stable_key is not null
  )
  delete from timeline_events r using ranked x where r.id = x.id and x.rn > 1;
  get diagnostics d = row_count; n := n + d;
  with ranked as (
    select id, row_number() over (
             partition by section, public._norm_txt(coalesce(label, hero_label)), public._norm_txt(value)
             order by coalesce(hidden, false), id) rn
      from firm_profile_facts
     where firm_id = p_firm
  )
  delete from firm_profile_facts r using ranked x where r.id = x.id and x.rn > 1;
  get diagnostics d = row_count; n := n + d;
  with ranked as (
    select id,
           first_value(id) over (
             partition by public._norm_txt(body), coalesce(source_urls[1], '')
             order by id) keeper,
           row_number() over (
             partition by public._norm_txt(body), coalesce(source_urls[1], '')
             order by id) rn
      from reviews
     where firm_id = p_firm and coalesce(body, '') <> ''
  )
  update founder_accounts fa set moved_to_review = r.keeper
    from ranked r
   where fa.moved_to_review = r.id and r.rn > 1;
  with ranked as (
    select id, row_number() over (
             partition by public._norm_txt(body), coalesce(source_urls[1], '')
             order by id) rn
      from reviews
     where firm_id = p_firm and coalesce(body, '') <> ''
  )
  delete from reviews r using ranked x where r.id = x.id and x.rn > 1;
  get diagnostics d = row_count; n := n + d;
  return n;
end $$;
revoke all on function public._checker_keep_one_exact(uuid) from public, anon, authenticated;

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
revoke all on function public._checker_place(uuid, text, jsonb, text, smallint, int, bigint) from public, anon, authenticated;

create or replace function public._checker_payload_items(p jsonb)
returns table(n int, section text, f jsonb, url text)
language plpgsql stable as $$
begin
  if jsonb_typeof(p->'sections') = 'object' then
    return query select c.n, c.section, c.f, c.url from public.checked_items(p) c where c.outcome = 'ok';
    return;
  end if;
  if jsonb_typeof(p->'records') = 'array' then
    return query
    select s.n::int, s.section, s.f, s.url from (
      select row_number() over () n,
        case r->>'field_path'
          when 'people' then 'people' when 'peopleMoves' then 'people'
          when 'funds' then 'funds' when 'latestRaise' then 'funds'
          when 'limitedPartners' then 'lps' when 'portfolio' then 'deals'
          when 'lawsuits' then 'legal' when 'regulatoryActions' then 'legal'
          when 'sanctions' then 'legal' when 'controversies' then 'legal'
          when 'posts' then 'founders' when 'reviews' then 'founders'
          else 'overview' end section,
        case when jsonb_typeof(r->'value') = 'object' then r->'value'
             else jsonb_build_object('label', r->>'field_path', 'value', r->>'value') end f,
        (select x->>'url' from jsonb_array_elements(case when jsonb_typeof(r->'sources') = 'array' then r->'sources' else '[]'::jsonb end) x limit 1) url
      from jsonb_array_elements(p->'records') r
    ) s;
  end if;
end $$;

create or replace function public.checker_publish_submission(p_id bigint) returns jsonb
language plpgsql security definer set search_path = bots, public as $$
declare sub bots.research_submissions; fid uuid; it record; lvl smallint; ncheck int; outcome text; reason text;
  pub int := 0; skip int := 0; fail int := 0; unconf int := 0; merged int := 0; noted int := 0;
begin
  select * into sub from research_submissions where id = p_id;
  if sub.id is null or not public._checker_publish_on() then
    return jsonb_build_object('ran', false);
  end if;
  select f.id into fid from firms f
   where f.deleted_at is null and f.registry_id = coalesce(public._registry_target(sub.registry_id), sub.registry_id)
   order by f.published desc limit 1;
  if fid is null or not public._lab_firm(fid) then
    return jsonb_build_object('ran', false, 'reason', 'not a lab firm');
  end if;
  for it in select * from public._checker_payload_items(sub.payload) loop
    begin
      ncheck := public._checker_check_n(it.section, it.url);
      select d.lvl, d.outcome, d.reason into lvl, outcome, reason
        from public._checker_decide(fid, it.section, it.f, it.url, ncheck, null) d;
      if outcome = 'published' then
        select p.outcome, p.reason into outcome, reason
          from public._checker_place(fid, it.section, it.f, it.url, lvl, ncheck, sub.id) p;
      end if;
    exception when others then
      outcome := 'failure'; reason := sqlerrm;
    end;
    if outcome = 'published' then pub := pub + 1;
    elsif outcome = 'merged' then merged := merged + 1;
    elsif outcome = 'note' then noted := noted + 1;
    elsif outcome = 'skipped' then skip := skip + 1;
    elsif outcome = 'unconfirmed' then unconf := unconf + 1;
    else fail := fail + 1; end if;
    if outcome in ('failure', 'unconfirmed') then
      insert into checker_holding(firm_id, origin, origin_id, kind, url, outcome, reason, item)
      values (fid, 'submission', sub.id, it.section, it.url,
              case when outcome = 'unconfirmed' then 'unconfirmed' else 'failure' end, reason, it.f);
    end if;
  end loop;
  return jsonb_build_object('ran', true, 'firm_id', fid, 'published', pub, 'merged', merged, 'note', noted,
    'skipped', skip, 'unconfirmed', unconf, 'failure', fail);
end $$;
revoke all on function public.checker_publish_submission(bigint) from public, anon, authenticated;

create or replace function public.checker_on_submission() returns trigger
language plpgsql security definer set search_path = bots, public as $$
begin
  if not public._checker_publish_on() then return null; end if;
  begin
    perform public.checker_publish_submission(new.id);
  exception when others then
    insert into checker_holding(firm_id, origin, origin_id, kind, outcome, reason, item)
    values (null, 'submission', new.id, 'row', 'failure', sqlerrm, new.payload);
  end;
  return null;
end $$;
revoke all on function public.checker_on_submission() from public, anon, authenticated;

drop trigger if exists checker_on_submission on bots.research_submissions;
create trigger checker_on_submission after insert on bots.research_submissions
  for each row execute function public.checker_on_submission();

do $$
declare f uuid; n int; total int := 0;
begin
  for f in select id from firms where deleted_at is null and public._lab_firm(id) loop
    n := public._checker_keep_one_exact(f);
    total := total + coalesce(n, 0);
  end loop;
  insert into bots.ingest_settings(key, value) values ('checker_exact_removed', total::text)
  on conflict (key) do update set value = excluded.value;
end $$;
