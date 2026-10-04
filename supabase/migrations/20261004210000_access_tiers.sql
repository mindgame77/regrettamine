-- Access tiers, enforced in the database.
-- visitor: landing rows 1–3, 2 reports (anon_key on report_views)
-- free:    landing rows 1–11, 7 reports, then the client sends them to /plans/
-- paid:    everything, while subscriptions.status = 'active'
--          and subscriptions.current_period_end > now()
--
-- Stripe renewal is not built. A future webhook, using the service role,
-- should call public.apply_subscription(profile_id, plan, status, current_period_end)
-- with current_period_end = payment time + one month.

create table public.subscriptions (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  plan text not null,
  status text not null,
  current_period_end timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.report_pages (
  slug text primary key references public.firms(slug) on delete cascade,
  html text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists touch_subscriptions on public.subscriptions;
create trigger touch_subscriptions before update on public.subscriptions
  for each row execute function public.touch_updated_at();

drop trigger if exists touch_report_pages on public.report_pages;
create trigger touch_report_pages before update on public.report_pages
  for each row execute function public.touch_updated_at();

alter table public.subscriptions enable row level security;
alter table public.report_pages enable row level security;

create policy subscriptions_select_own on public.subscriptions
  for select to authenticated
  using (profile_id = auth.uid());

-- No browser policy on report_pages. Only security definer RPCs read the HTML.

-- ---------------------------------------------------------------------------
-- Tier helpers
-- ---------------------------------------------------------------------------

create or replace function public.is_paid(p_profile uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.subscriptions s
    where s.profile_id = p_profile
      and s.status = 'active'
      and s.current_period_end > now()
  );
$$;

create or replace function public.access_tier()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when auth.uid() is null then 'visitor'
    when public.is_paid(auth.uid()) then 'paid'
    else 'free'
  end;
$$;

create or replace function public.tier_list_limit(p_tier text)
returns integer
language sql
immutable
as $$
  select case p_tier
    when 'paid' then null
    when 'free' then 11
    else 3
  end;
$$;

create or replace function public.firm_list_row(f public.firms)
returns jsonb
language sql
immutable
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'id', f.slug,
    'name', f.name,
    'ini', f.initials,
    'short', f.short_name,
    'hq', f.hq,
    'metro', f.metro,
    'since', f.founded_year,
    'type', f.firm_type,
    'aum', f.aum_billions,
    'aumAsOf', f.aum_as_of,
    'aumStale', f.aum_stale,
    'aumSrc', f.aum_source,
    'score', f.list_score,
    'v2', f.list_v2,
    'band', f.list_band,
    'legal', f.list_legal_active,
    'legalNote', f.legal_note,
    'updated', to_char(f.updated_on, 'YYYY-MM-DD'),
    'updatedTs', f.updated_ts,
    'updatedS', f.updated_label,
    'old', f.list_previous_score,
    'lo', f.list_range_low,
    'hi', f.list_range_high,
    'cov', f.list_coverage,
    'verdict', f.list_verdict,
    'report', f.report_slug
  ));
$$;

-- Stripe webhook hook. The browser cannot call this.
-- Pass current_period_end one month after payment. Renewal is a later webhook.
create or replace function public.apply_subscription(
  p_profile_id uuid,
  p_plan text,
  p_status text,
  p_current_period_end timestamptz
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_profile_id is null or p_plan is null or p_status is null or p_current_period_end is null then
    raise exception 'apply_subscription needs a profile, plan, status, and current_period_end';
  end if;
  insert into public.subscriptions (profile_id, plan, status, current_period_end)
  values (p_profile_id, p_plan, p_status, p_current_period_end)
  on conflict (profile_id) do update
    set plan = excluded.plan,
        status = excluded.status,
        current_period_end = excluded.current_period_end,
        updated_at = now();
end;
$$;

comment on function public.apply_subscription(uuid, text, text, timestamptz) is
  'Stripe webhook hook. Not callable by anon or authenticated. Set status to active and current_period_end to one month after payment. A user is paid only while status = active and current_period_end > now().';

-- The build uploads one rendered report. The service role key stays on the server.
create or replace function public.store_report_page(p_slug text, p_html text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_slug is null or p_html is null or p_slug !~ '^[a-z0-9-]{1,80}$' then
    raise exception 'invalid report page';
  end if;
  insert into public.report_pages (slug, html)
  values (p_slug, p_html)
  on conflict (slug) do update
    set html = excluded.html,
        updated_at = now();
end;
$$;

-- ---------------------------------------------------------------------------
-- Landing list and search. Names outside the window stay name + slug only.
-- ---------------------------------------------------------------------------

create or replace function public.landing_funds()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tier text := public.access_tier();
  v_limit integer := public.tier_list_limit(v_tier);
  v_total integer;
  v_funds jsonb;
begin
  select count(*) into v_total
  from public.firms
  where published and not is_test;

  select coalesce(jsonb_agg(public.firm_list_row(f) order by ranked.rank), '[]'::jsonb)
  into v_funds
  from public.firms f
  join (
    select id, row_number() over (order by list_score desc nulls last, name) as rank
    from public.firms
    where published and not is_test
  ) ranked on ranked.id = f.id
  where v_limit is null or ranked.rank <= v_limit;

  return jsonb_build_object(
    'tier', v_tier,
    'limit', v_limit,
    'total', v_total,
    'funds', v_funds
  );
end;
$$;

create or replace function public.search_funds(q text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  cleaned text;
  v_tier text := public.access_tier();
  v_limit integer := public.tier_list_limit(v_tier);
  v_hits jsonb;
begin
  cleaned := left(regexp_replace(btrim(coalesce(q, '')), '[%_\\]', '', 'g'), 80);
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
    select id, row_number() over (order by list_score desc nulls last, name) as rank
    from public.firms
    where published and not is_test
  ) ranked on ranked.id = f.id
  where f.name ilike '%' || cleaned || '%'
     or f.slug ilike '%' || cleaned || '%';

  return v_hits;
end;
$$;

-- ---------------------------------------------------------------------------
-- Report open. Counts on the server. Refuses past 2 / 7. Paid is unlimited.
-- Re-opening a fund that already has a row does not take another slot.
-- ---------------------------------------------------------------------------

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

-- Copies anon report_views onto the signed-in profile, up to the free cap.
-- Slugs the browser invents are ignored. Only rows this anon key already opened count.
create or replace function public.carry_anon_views(p_anon_key text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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
$$;

create or replace function public.my_report_slugs()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(f.slug order by f.name), '[]'::jsonb)
  from public.report_views v
  join public.firms f on f.id = v.firm_id
  where v.profile_id = auth.uid();
$$;

create or replace function public.my_watch_slugs()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(f.slug order by f.name), '[]'::jsonb)
  from public.watchlist w
  join public.firms f on f.id = w.firm_id
  where w.profile_id = auth.uid();
$$;

create or replace function public.firm_id_for_slug(p_slug text)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id
  from public.firms
  where slug = p_slug and published and not is_test;
$$;

create or replace function public.watch_fund(p_slug text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  fid uuid;
  n integer;
begin
  if uid is null then
    return jsonb_build_object('needAuth', true);
  end if;
  select id into fid
  from public.firms
  where slug = p_slug and published and not is_test;
  if fid is null then
    return jsonb_build_object('error', 'That fund is not in the database yet.');
  end if;
  if exists (select 1 from public.watchlist where profile_id = uid and firm_id = fid) then
    return jsonb_build_object('saved', true);
  end if;
  select count(*) into n from public.watchlist where profile_id = uid;
  if n >= 100 then
    return jsonb_build_object('full', true);
  end if;
  insert into public.watchlist (profile_id, firm_id) values (uid, fid);
  return jsonb_build_object('saved', true);
exception
  when check_violation then
    return jsonb_build_object('full', true);
end;
$$;

create or replace function public.unwatch_fund(p_slug text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.watchlist w
  using public.firms f
  where w.firm_id = f.id
    and w.profile_id = auth.uid()
    and f.slug = p_slug;
end;
$$;

-- ---------------------------------------------------------------------------
-- Lock the anon key out of the full catalog and the full reports.
-- The bundle stays available to the service role for the Pages build.
-- ---------------------------------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array[
    'firms', 'funds', 'fund_entities', 'fund_people', 'investments', 'reviews',
    'legal_matter_firms', 'regulatory_records', 'sanctions_checks',
    'fact_sources', 'takeaways', 'ask_questions', 'copy_blocks', 'page_chips',
    'firm_meta_items', 'list_items', 'portfolio_metrics', 'firm_ranks',
    'evidence_cards', 'score_results',
    'press_item_firms', 'people', 'portfolio_companies', 'company_founders',
    'review_ratings', 'legal_matters', 'legal_matter_parties', 'filings',
    'docket_entries', 'legal_groups', 'legal_group_items', 'press_items',
    'sources', 'evidence_lines', 'score_result_parts', 'score_lines', 'score_inputs'
  ]
  loop
    execute format('drop policy if exists %I on public.%I', t || '_public_read', t);
  end loop;
end $$;

-- Clients must not mint a report_views row and then receive the HTML as a repeat.
drop policy if exists report_views_insert on public.report_views;
drop policy if exists report_views_update on public.report_views;

do $mig$
declare
  src text;
  def text;
begin
  select pg_get_functiondef('public.published_site_bundle()'::regprocedure) into src;
  if src not ilike '%security definer%' then
    def := replace(src, 'AS $function$', E'SECURITY DEFINER\n AS $function$');
    if def = src then
      raise exception 'could not mark published_site_bundle security definer';
    end if;
    execute def;
  end if;
end
$mig$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    begin
      execute 'alter role service_role bypassrls';
    exception
      when insufficient_privilege then
        null;
    end;
  end if;
end $$;

revoke all on function public.published_site_bundle() from public, anon, authenticated;
grant execute on function public.published_site_bundle() to service_role;

revoke all on function public.is_paid(uuid) from public;
revoke all on function public.access_tier() from public;
revoke all on function public.tier_list_limit(text) from public;
revoke all on function public.firm_list_row(public.firms) from public;
revoke all on function public.apply_subscription(uuid, text, text, timestamptz) from public;
revoke all on function public.store_report_page(text, text) from public;
revoke all on function public.landing_funds() from public;
revoke all on function public.search_funds(text) from public;
revoke all on function public.open_report(text, text) from public;
revoke all on function public.carry_anon_views(text) from public;
revoke all on function public.my_report_slugs() from public;
revoke all on function public.my_watch_slugs() from public;
revoke all on function public.firm_id_for_slug(text) from public;
revoke all on function public.watch_fund(text) from public;
revoke all on function public.unwatch_fund(text) from public;

grant execute on function public.access_tier() to anon, authenticated, service_role;
grant execute on function public.is_paid(uuid) to authenticated, service_role;
grant execute on function public.landing_funds() to anon, authenticated, service_role;
grant execute on function public.search_funds(text) to anon, authenticated, service_role;
grant execute on function public.open_report(text, text) to anon, authenticated, service_role;
grant execute on function public.carry_anon_views(text) to authenticated, service_role;
grant execute on function public.my_report_slugs() to authenticated, service_role;
grant execute on function public.my_watch_slugs() to authenticated, service_role;
grant execute on function public.firm_id_for_slug(text) to authenticated, service_role;
grant execute on function public.watch_fund(text) to authenticated, service_role;
grant execute on function public.unwatch_fund(text) to authenticated, service_role;
grant execute on function public.apply_subscription(uuid, text, text, timestamptz) to service_role;
grant execute on function public.store_report_page(text, text) to service_role;
