-- One switch for the paywall. Proposed, not applied to live.
-- app_settings.lock_enabled = false: firm_page (through unlock_firm), firm_activity_list,
-- and open_report return the full payload. No credit is spent and no report view is counted.
-- app_settings.lock_enabled = true: today's lock, blur, and credit spend.
-- Rollback: update public.app_settings set value = 'true' where key = 'lock_enabled';
-- or revert this migration.

create table public.app_settings (
  key text primary key,
  value text not null
);

alter table public.app_settings enable row level security;
revoke all on table public.app_settings from public, anon, authenticated;
grant select, update on table public.app_settings to service_role;

insert into public.app_settings(key, value) values ('lock_enabled', 'false');

create or replace function public.lock_enabled()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select value from public.app_settings where key = 'lock_enabled'), 'true') is distinct from 'false'
$$;

revoke all on function public.lock_enabled() from public, anon, authenticated;
grant execute on function public.lock_enabled() to service_role;

create or replace function public.unlock_firm(p_slug text, p_anon uuid, p_spend boolean default true, p_email text default null)
returns json language plpgsql security definer set search_path = public as $$
declare b public.check_balances; f uuid; ix boolean; h text; ip_cap constant int := 4;
  need boolean; qid text; sk text; em text;
begin
  -- Lock off: full details, no balance row, no credit, no on-demand job. The rest of this function is today's spend path.
  if not public.lock_enabled() then
    select id into f from firms where slug = p_slug and deleted_at is null and published and not coalesce(is_test, false) and data_status = 'real';
    if f is null then return json_build_object('status','not_found'); end if;
    return json_build_object('status','ok','details', public._firm_details_cached(f));
  end if;
  b := _balance(p_anon);
  h := _ip_hash();
  select id, indexable into f, ix from firms where slug = p_slug and deleted_at is null and published and not coalesce(is_test, false) and data_status = 'real';
  if f is null then return json_build_object('status','not_found'); end if;
  if coalesce((select sum(case when kind like 'spend_%' then 1 when kind = 'refund_ondemand' then -1 else 0 end) from check_events
               where balance_id = b.id and firm_id = f), 0) <= 0 then
    if not p_spend then return json_build_object('status','locked'); end if;
    need := _ondemand_needed(f);
    if need then qid := _firm_queue_id(f); end if;
    if not ix and qid is null then return json_build_object('status','unchecked'); end if;
    if b.free_left > 0 and auth.uid() is null and h is not null
       and (select count(*) from check_events where ip_hash = h and kind = 'spend_free' and created_at > now() - interval '30 days') >= ip_cap then
      return json_build_object('status','need_signup');
    end if;
    if b.free_left > 0 then
      update check_balances set free_left = free_left - 1, updated_at = now() where id = b.id;
      insert into check_events(balance_id, firm_id, kind, amount, ip_hash) values (b.id, f, 'spend_free', -1, case when auth.uid() is null then h end);
      sk := 'spend_free';
    elsif b.paid_left > 0 then
      update check_balances set paid_left = paid_left - 1, updated_at = now() where id = b.id;
      insert into check_events(balance_id, firm_id, kind, amount) values (b.id, f, 'spend_paid', -1);
      sk := 'spend_paid';
    elsif auth.uid() is null then return json_build_object('status','need_signup');
    else return json_build_object('status','out');
    end if;
    em := lower(nullif(btrim(coalesce((select email from auth.users where id = auth.uid()), p_email, '')), ''));
    if em is not null and em !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then em := null; end if;
    if need and qid is not null then
      perform _ondemand_enqueue(f, qid, b.id, sk, em, p_anon);
    elsif em is not null then
      perform _ondemand_save_email(f, b.id, sk, em, p_anon);
    end if;
  end if;
  return json_build_object('status','ok','details', public._firm_details_cached(f));
end $$;

CREATE OR REPLACE FUNCTION public.firm_activity_list(p_slug text, p_anon uuid, p_kind text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b public.check_balances; f uuid; out jsonb;
begin
  if public.lock_enabled() then
    if p_anon is null then return json_build_object('status', 'locked'); end if;
  end if;
  select id into f from firms where slug = p_slug and deleted_at is null and published and not coalesce(is_test, false) and data_status = 'real';
  if f is null then return json_build_object('status', 'not_found'); end if;
  if public.lock_enabled() then
    b := _balance(p_anon);
    if coalesce((select sum(case when kind like 'spend_%' then 1 when kind = 'refund_ondemand' then -1 else 0 end) from check_events
                 where balance_id = b.id and firm_id = f), 0) <= 0 then
      return json_build_object('status', 'locked');
    end if;
  end if;
  if p_kind = 'deals' then
    select coalesce(jsonb_agg(_activity_deal(i, c) order by i.invested_on desc nulls last, c.name), '[]') into out
      from investments i left join portfolio_companies c on c.id = i.company_id
     where i.firm_id = f and i.data_status = 'real';
  elsif p_kind = 'revs' then
    select coalesce(jsonb_agg(_activity_review(r, c) order by (r.review_type = 'founder') desc, r.reviewed_on desc nulls last, r.created_at desc), '[]') into out
      from reviews r left join portfolio_companies c on c.id = r.company_id
     where r.firm_id = f and r.is_public and r.moderation_status = 'approved';
  else
    return json_build_object('status', 'bad_kind');
  end if;
  return json_build_object('status', 'ok', 'items', out);
end $function$;

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
$$;
