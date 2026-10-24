-- Publish rule (approved 2026-10-23): a firm has a public page when published, real, not test, not deleted.
-- launch_page no longer gates content RPCs. CREATE OR REPLACE keeps existing grants. Previous definitions: backups/pre-publish-rule-2026-10-23.

CREATE OR REPLACE FUNCTION public.unlock_firm(p_slug text, p_anon uuid, p_spend boolean DEFAULT true)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b public.check_balances := _balance(p_anon); f uuid; h text := _ip_hash(); ip_cap constant int := 4;
begin
  select id into f from firms where slug = p_slug and deleted_at is null and published and not coalesce(is_test, false) and data_status = 'real';
  if f is null then return json_build_object('status','not_found'); end if;
  if not exists (select 1 from check_events where balance_id = b.id and firm_id = f and kind like 'spend_%') then
    if not p_spend then return json_build_object('status','locked'); end if;
    if b.free_left > 0 and auth.uid() is null and h is not null
       and (select count(*) from check_events where ip_hash = h and kind = 'spend_free' and created_at > now() - interval '30 days') >= ip_cap then
      return json_build_object('status','need_signup');
    end if;
    if b.free_left > 0 then
      update check_balances set free_left = free_left - 1, updated_at = now() where id = b.id;
      insert into check_events(balance_id, firm_id, kind, amount, ip_hash) values (b.id, f, 'spend_free', -1, case when auth.uid() is null then h end);
    elsif b.paid_left > 0 then
      update check_balances set paid_left = paid_left - 1, updated_at = now() where id = b.id;
      insert into check_events(balance_id, firm_id, kind, amount) values (b.id, f, 'spend_paid', -1);
    elsif auth.uid() is null then return json_build_object('status','need_signup');
    else return json_build_object('status','out');
    end if;
  end if;
  return json_build_object('status','ok','details', public.firm_details(f));
end $function$
;

CREATE OR REPLACE FUNCTION public.firm_case_outline(p_slug text)
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(json_agg(json_build_object('row', rn, 'items', items) order by rn), '[]'::json) from (
    select c.rn, json_agg(json_build_object('kind', c.kind, 'year', c.yr, 'status', c.status)
      order by (c.status = 'active') desc nulls last, c.ord) items
    from firms f, public._firm_cases(f.id) c
    where f.slug = p_slug and f.deleted_at is null and f.published and not coalesce(f.is_test, false) and f.data_status = 'real'
    group by c.rn) g
$function$
;

CREATE OR REPLACE FUNCTION public.firm_suggest(q text)
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with t as (select lower(trim(q)) t), m as (
    select f.slug, f.name, f.short_name, f.hq,
      case when lower(f.name) like t || '%' or lower(coalesce(f.short_name, '')) like t || '%' or f.slug like t || '%' then 0
           when lower(f.name) ~ ('\m' || regexp_replace(t, '([^a-z0-9 ])', '\\\1', 'g')) then 1 else 2 end r
    from firms f, t
    where f.published and not coalesce(f.is_test, false) and f.data_status = 'real' and f.deleted_at is null and length(t) > 0
      and (lower(f.name) like '%' || t || '%' or lower(coalesce(f.short_name, '')) like '%' || t || '%' or f.slug like '%' || t || '%'))
  select coalesce(json_agg(json_build_object('slug', slug, 'name', name, 'short_name', short_name, 'hq', hq) order by r, name), '[]')
  from (select * from m order by r, name limit 8) x
$function$
;

CREATE OR REPLACE FUNCTION public.bump_firm_check(p_slug text, p_anon uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare f firms; v text; qid text; q research_queue; front int;
begin
  select * into f from firms where slug = p_slug and deleted_at is null and published and not coalesce(is_test, false) and data_status = 'real';
  if f.id is null then return json_build_object('status', 'not_found'); end if;
  if _firm_checks_done(f.id) >= 10 then return json_build_object('status', 'complete'); end if;
  v := case when auth.uid() is not null then 'u:' || auth.uid() when p_anon is not null then 'a:' || p_anon end;
  if v is null then return json_build_object('status', 'no_visitor'); end if;
  if exists (select 1 from check_bumps where firm_id = f.id and visitor = v and at > now() - interval '10 minutes')
     or (select count(*) from check_bumps where visitor = v and at > now() - interval '1 hour') >= 20 then
    return json_build_object('status', 'rate_limited'); end if;
  insert into check_bumps (firm_id, visitor) values (f.id, v) on conflict (firm_id, visitor) do update set at = now();
  delete from check_bumps where at < now() - interval '1 day';
  qid := _firm_queue_id(f.id);
  if qid is null then return json_build_object('status', 'not_in_queue'); end if;
  select * into q from research_queue where registry_id = qid for update;
  if q.status <> 'queued' then return json_build_object('status', q.status); end if; -- never re-queue claimed/submitted/...
  select min(priority) into front from research_queue where status = 'queued' and registry_id <> qid;
  if front is null or q.priority < front then return json_build_object('status', 'queued', 'front', true); end if;
  update research_queue set priority = front - 1, bumped_at = now(), updated_at = now() where registry_id = qid;
  return json_build_object('status', 'queued', 'front', true, 'bumped', true);
end $function$
;

CREATE OR REPLACE FUNCTION public.notify_when_checked(p_slug text, p_email text, p_anon uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare f firms; em text;
begin
  select * into f from firms where slug = p_slug and deleted_at is null and published and not coalesce(is_test, false) and data_status = 'real';
  if f.id is null then return json_build_object('status', 'not_found'); end if;
  em := lower(trim(coalesce((select email from auth.users where id = auth.uid()), p_email, '')));
  if em !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(em) > 200 then return json_build_object('status', 'bad_email'); end if;
  if auth.uid() is null and p_anon is null then return json_build_object('status', 'no_visitor'); end if;
  if exists (select 1 from check_requests where firm_id = f.id and lower(email) = em and notified_at is null) then
    return json_build_object('status', 'ok'); end if;
  if (select count(*) from check_requests where created_at > now() - interval '1 hour'
       and (user_id = auth.uid() or (auth.uid() is null and anon_id = p_anon))) >= 10 then
    return json_build_object('status', 'rate_limited'); end if;
  insert into check_requests (query, email, anon_id, user_id, firm_id, status)
    values (f.name, em, p_anon, auth.uid(), f.id, 'running');
  return json_build_object('status', 'ok');
end $function$
;

CREATE OR REPLACE FUNCTION public.firm_check_status(p_slug text)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare f firms; q research_queue; qid text;
begin
  select * into f from firms where slug = p_slug and deleted_at is null and published and not coalesce(is_test, false) and data_status = 'real';
  if f.id is null then return json_build_object('status', 'not_found'); end if;
  qid := _firm_queue_id(f.id);
  if qid is not null then select * into q from research_queue where registry_id = qid; end if;
  return json_build_object('status', 'ok', 'done', _firm_checks_done(f.id), 'total', 10,
    'complete', _firm_checks_done(f.id) >= 10, 'queue', q.status, 'started_at', case when q.status = 'claimed' then q.claimed_at end,
    'checks', (select json_agg(json_build_object('n', n, 'state', state, 'count', count_label) order by n) from firm_check_rows where firm_id = f.id));
end $function$
;

CREATE OR REPLACE FUNCTION public.firm_page(p_slug text, p_anon uuid, p_spend boolean DEFAULT false)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare f firms; u json; open boolean; secs jsonb := '[]'; s page_sections; it jsonb; hero jsonb; q research_queue; qid text;
begin
  select * into f from firms where slug = p_slug and deleted_at is null and published and not coalesce(is_test, false) and data_status = 'real';
  if f.id is null then return json_build_object('status', 'not_found'); end if;
  u := unlock_firm(p_slug, p_anon, p_spend);
  open := u->>'status' = 'ok';
  if u->>'status' not in ('ok', 'locked') then return u; end if;
  for s in select * from page_sections where enabled order by sort_order loop
    it := _sec_items(s.key, f.id);
    continue when jsonb_array_length(it) = 0;
    secs := secs || jsonb_build_object('key', s.key, 'title', s.title, 'subtitle', s.subtitle, 'renderer', s.renderer,
      'count', jsonb_array_length(it), 'unit', case when jsonb_array_length(it) = 1 then s.unit_one else s.unit_many end,
      'teaser', it->0->>'head', 'items', case when open then it end);
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('label', hero_label, 'value', hero_value, 'anchor', section,
      'src', _src('firm_profile_facts', id)) order by section desc, sort_order), '[]') into hero
    from firm_profile_facts where firm_id = f.id and hero_label is not null and exists (select 1 from fact_sources where fact_type = 'firm_profile_facts' and fact_id = firm_profile_facts.id);
  qid := _firm_queue_id(f.id);
  if qid is not null then select * into q from research_queue where registry_id = qid; end if;
  return json_build_object('status', 'ok', 'open', open,
    'firm', json_build_object('slug', f.slug, 'name', f.name, 'short_name', f.short_name, 'hq', f.hq),
    'hero', hero, 'sections', secs,
    'checks', (select json_agg(json_build_object('n', n, 'title', title, 'descr', descr, 'state', state, 'count', count_label, 'searched_at', searched_at,
        'items', case when open then (select coalesce(json_agg(json_build_object('title', i.title, 'year', i.yr, 'status', i.status, 'note', i.note, 'who', i.who) order by i.yr desc nulls last, i.title), '[]') from check_findings(source_submission) i where i.k = n) end,
        'itemized', (select count(*) from check_findings(source_submission) i where i.k = n)) order by n) from firm_check_rows where firm_id = f.id),
    'queue', q.status, 'started_at', case when q.status = 'claimed' then q.claimed_at end,
    'details', u->'details', 'outline', case when not open then firm_case_outline(p_slug) end);
end $function$
;

CREATE OR REPLACE FUNCTION public.watch_fund(p_slug text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid();
  fid uuid;
begin
  if uid is null then
    return jsonb_build_object('needAuth', true);
  end if;
  select id into fid from public.firms where slug = p_slug and deleted_at is null and published and not coalesce(is_test, false) and data_status = 'real';
  if fid is null then
    return jsonb_build_object('error', 'That fund is not in the database yet.');
  end if;
  insert into public.watchlist (profile_id, firm_id) values (uid, fid) on conflict do nothing;
  perform public.sync_watch_alerts(uid);
  return jsonb_build_object('saved', true);
end;
$function$
;
