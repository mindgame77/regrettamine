-- Recreate the twelve old website functions exactly as they were before
-- 20261028060000_drop_old_site_rpcs.sql dropped them.
-- Not applied by scripts/migrate.py. Run this by hand.
-- anon and authenticated stay unable to call them. service_role can.

CREATE OR REPLACE FUNCTION public.carry_anon_views(p_anon_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid();
  v_tier text;
  v_cap integer;
  v_anon integer;
  v_extra integer;
  v_used integer;
  rec record;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'auth');
  end if;
  if p_anon_key is null or p_anon_key !~ '^[A-Za-z0-9_-]{8,80}$' then
    return jsonb_build_object('ok', true, 'copied', 0);
  end if;

  v_tier := public.access_tier();
  select anonymous_free_reports, registered_extra_reports
  into v_anon, v_extra
  from public.gating_policies
  where code = 'default';
  v_anon := coalesce(v_anon, 2);
  v_extra := coalesce(v_extra, 5);
  v_cap := case when v_tier = 'paid' then null else v_anon + v_extra end;
  select count(*) into v_used from public.report_views where profile_id = uid;

  for rec in
    select firm_id
    from public.report_views
    where anon_key = p_anon_key
  loop
    exit when v_cap is not null and v_used >= v_cap;
    if exists (
      select 1 from public.report_views
      where profile_id = uid and firm_id = rec.firm_id
    ) then
      continue;
    end if;
    insert into public.report_views (profile_id, firm_id, source, dwell_ms, counted)
    values (uid, rec.firm_id, 'carry', 0, true);
    v_used := v_used + 1;
  end loop;

  return jsonb_build_object('ok', true, 'used', v_used);
end;
$function$;

CREATE OR REPLACE FUNCTION public.fact_record_count()
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select count(*) from public.fact_events where import_run_id is null or data_status = 'real';
$function$;

CREATE OR REPLACE FUNCTION public.firm_id_for_slug(p_slug text)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select id
  from public.firms
  where slug = p_slug and published and not is_test;
$function$;

CREATE OR REPLACE FUNCTION public.landing_funds()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tier text := public.access_tier();
  v_limit integer := public.tier_list_limit(v_tier);
  v_total integer;
  v_funds jsonb;
begin
  select count(*) into v_total
  from public.firms
  where published and indexable and not is_test;

  select coalesce(jsonb_agg(public.firm_list_row(f) order by ranked.rank), '[]'::jsonb)
  into v_funds
  from public.firms f
  join (
    select id, row_number() over (order by coalesce(list_score_exact, list_score) desc nulls last, name) as rank
    from public.firms
    where published and indexable and not is_test
  ) ranked on ranked.id = f.id
  where v_limit is null or ranked.rank <= v_limit;

  return jsonb_build_object(
    'tier', v_tier,
    'limit', v_limit,
    'total', v_total,
    'funds', v_funds
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.my_alert_funds()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(item order by item->>'name'), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'slug', f.slug,
      'name', f.name,
      'alerts', coalesce(w.alerts, false) or coalesce(s.enabled, false),
      'new_legal_matter', coalesce(s.new_legal_matter, false),
      'score_change', coalesce(s.score_change, false),
      'opened', exists (
        select 1 from public.report_views v
        where v.profile_id = auth.uid() and v.firm_id = f.id
      )
    ) as item
    from public.firms f
    left join public.watchlist w
      on w.firm_id = f.id and w.profile_id = auth.uid()
    left join public.fund_alert_settings s
      on s.firm_id = f.id and s.profile_id = auth.uid()
    where auth.uid() is not null
      and f.published
      and not f.is_test
      and (
        w.profile_id is not null
        or s.profile_id is not null
        or exists (
          select 1 from public.report_views v
          where v.profile_id = auth.uid() and v.firm_id = f.id
        )
      )
  ) rows;
$function$;

CREATE OR REPLACE FUNCTION public.my_report_slugs()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(f.slug order by f.name), '[]'::jsonb)
  from public.report_views v
  join public.firms f on f.id = v.firm_id
  where v.profile_id = auth.uid();
$function$;

CREATE OR REPLACE FUNCTION public.my_watch_alerts()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'new_legal_matter', coalesce(a.new_legal_matter, false),
    'score_change', coalesce(a.score_change, false)
  )
  from public.alert_preferences a
  where a.profile_id = auth.uid();
$function$;

CREATE OR REPLACE FUNCTION public.my_watch_slugs()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(f.slug order by f.name), '[]'::jsonb)
  from public.watchlist w
  join public.firms f on f.id = w.firm_id
  where w.profile_id = auth.uid();
$function$;

CREATE OR REPLACE FUNCTION public.open_report(p_slug text, p_anon_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid();
  fid uuid;
  v_tier text := public.access_tier();
  v_html text;
  v_cap integer;
  v_anon integer;
  v_extra integer;
  v_used integer;
  v_existing uuid;
begin
  if p_slug is null or p_slug !~ '^[a-z0-9-]{1,80}$' then
    return jsonb_build_object('ok', false, 'reason', 'missing');
  end if;

  select id into fid
  from public.firms
  where slug = p_slug and published and not is_test;
  if fid is null then
    return jsonb_build_object('ok', false, 'reason', 'missing');
  end if;

  select html into v_html from public.report_pages where slug = p_slug;

  if v_html is null or v_html = '' then
    select b.payload->>'html' into v_html
    from public.report_bundles b
    where b.firm_id = fid;
  end if;

  if v_html is null then
    return jsonb_build_object('ok', false, 'reason', 'unpublished', 'tier', v_tier);
  end if;

  -- Lock off: hand back the report and do not count a view or spend a credit.
  if not public.lock_enabled() then
    return jsonb_build_object('ok', true, 'html', v_html, 'repeat', true, 'tier', v_tier);
  end if;

  if uid is null and (p_anon_key is null or p_anon_key !~ '^[A-Za-z0-9_-]{8,80}$') then
    return jsonb_build_object('ok', false, 'reason', 'anon', 'tier', v_tier);
  end if;

  perform pg_advisory_xact_lock(hashtext(coalesce(uid::text, 'anon:' || p_anon_key)));

  if uid is null then
    select id into v_existing
    from public.report_views
    where anon_key = p_anon_key and firm_id = fid;
  else
    select id into v_existing
    from public.report_views
    where profile_id = uid and firm_id = fid;
  end if;

  if v_existing is not null then
    update public.report_views
    set last_opened_at = now(), counted = true
    where id = v_existing;
    return jsonb_build_object(
      'ok', true,
      'html', v_html,
      'repeat', true,
      'tier', v_tier
    );
  end if;

  select anonymous_free_reports, registered_extra_reports
  into v_anon, v_extra
  from public.gating_policies
  where code = 'default';
  v_anon := coalesce(v_anon, 2);
  v_extra := coalesce(v_extra, 5);
  if v_tier = 'paid' then
    v_cap := null;
  elsif v_tier = 'free' then
    v_cap := v_anon + v_extra;
  else
    v_cap := v_anon;
  end if;

  if uid is null then
    select count(*) into v_used from public.report_views where anon_key = p_anon_key;
  else
    select count(*) into v_used from public.report_views where profile_id = uid;
  end if;

  if v_cap is not null and v_used >= v_cap then
    return jsonb_build_object(
      'ok', false,
      'reason', 'limit',
      'plans', v_tier = 'free',
      'tier', v_tier,
      'used', v_used,
      'cap', v_cap
    );
  end if;

  insert into public.report_views (profile_id, anon_key, firm_id, source, dwell_ms, counted)
  values (
    uid,
    case when uid is null then p_anon_key else null end,
    fid,
    'report',
    0,
    true
  );

  return jsonb_build_object(
    'ok', true,
    'html', v_html,
    'repeat', false,
    'tier', v_tier,
    'used', v_used + 1,
    'cap', v_cap
  );
exception
  when unique_violation then
    return jsonb_build_object(
      'ok', true,
      'html', v_html,
      'repeat', true,
      'tier', v_tier
    );
end;
$function$;

CREATE OR REPLACE FUNCTION public.public_firm_id(p_slug text)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select id
  from public.firms
  where slug = p_slug
    and published
    and not is_test;
$function$;

CREATE OR REPLACE FUNCTION public.search_funds(q text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  cleaned text;
  v_tier text := public.access_tier();
  v_limit integer := public.tier_list_limit(v_tier);
  v_hits jsonb;
begin
  cleaned := left(regexp_replace(btrim(coalesce(q, '')), '[%_\\\\]', '', 'g'), 80);
  if cleaned = '' then
    return '[]'::jsonb;
  end if;

  select coalesce(jsonb_agg(
    case
      when v_limit is null or ranked.rank <= v_limit then
        public.firm_list_row(f) || jsonb_build_object(
          'slug', f.slug,
          'rank', ranked.rank,
          'inTier', true
        )
      else jsonb_build_object(
        'id', f.slug,
        'name', f.name,
        'slug', f.slug,
        'rank', ranked.rank,
        'inTier', false
      )
    end
    order by ranked.rank
  ), '[]'::jsonb)
  into v_hits
  from public.firms f
  join (
    select id, row_number() over (order by coalesce(list_score_exact, list_score) desc nulls last, name) as rank
    from public.firms
    where published and indexable and not is_test
  ) ranked on ranked.id = f.id
  where f.name ilike '%' || cleaned || '%'
     or f.slug ilike '%' || cleaned || '%';

  return v_hits;
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_fund_alert(p_slug text, p_on boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid();
  fid uuid;
  n integer;
begin
  if uid is null then
    return jsonb_build_object('needAuth', true);
  end if;
  if p_slug is null or p_slug !~ '^[a-z0-9-]{1,80}$' then
    return jsonb_build_object('ok', false, 'reason', 'missing');
  end if;
  select id into fid
  from public.firms
  where slug = p_slug and published and not is_test;
  if fid is null then
    return jsonb_build_object('ok', false, 'reason', 'missing');
  end if;

  if coalesce(p_on, false) then
    if not public.can_alert_fund(uid, fid) then
      return jsonb_build_object('ok', false, 'reason', 'unopened');
    end if;
    if not exists (
      select 1 from public.watchlist where profile_id = uid and firm_id = fid
    ) then
      select count(*) into n from public.watchlist where profile_id = uid;
      if n >= 100 then
        return jsonb_build_object('full', true);
      end if;
      insert into public.watchlist (profile_id, firm_id, alerts)
      values (uid, fid, false);
    end if;
    insert into public.alert_preferences (profile_id)
    values (uid)
    on conflict (profile_id) do nothing;
    update public.alert_preferences
    set new_legal_matter = true, score_change = true, updated_at = now()
    where profile_id = uid;
    perform public.sync_watch_alerts(uid);
    return jsonb_build_object('ok', true, 'on', true);
  end if;

  update public.alert_preferences
  set new_legal_matter = false, score_change = false, updated_at = now()
  where profile_id = uid;
  perform public.sync_watch_alerts(uid);
  return jsonb_build_object('ok', true, 'on', false);
exception
  when check_violation then
    if sqlerrm ilike '%watchlist full%' then
      return jsonb_build_object('full', true);
    end if;
    return jsonb_build_object('ok', false, 'reason', 'unopened');
end;
$function$;

revoke all on function
  public.carry_anon_views(text),
  public.fact_record_count(),
  public.firm_id_for_slug(text),
  public.landing_funds(),
  public.my_alert_funds(),
  public.my_report_slugs(),
  public.my_watch_alerts(),
  public.my_watch_slugs(),
  public.public_firm_id(text),
  public.search_funds(text),
  public.set_fund_alert(text, boolean),
  public.open_report(text, text)
from public, anon, authenticated;

grant execute on function
  public.carry_anon_views(text),
  public.fact_record_count(),
  public.firm_id_for_slug(text),
  public.landing_funds(),
  public.my_alert_funds(),
  public.my_report_slugs(),
  public.my_watch_alerts(),
  public.my_watch_slugs(),
  public.public_firm_id(text),
  public.search_funds(text),
  public.set_fund_alert(text, boolean),
  public.open_report(text, text)
to service_role;
