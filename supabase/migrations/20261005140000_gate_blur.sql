-- A gated open_report returns only the limit. The score and the report body stay on the server.

create or replace function public.open_report(p_slug text, p_anon_key text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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
$$;
