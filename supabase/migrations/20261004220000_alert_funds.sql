-- Per-fund alerts. A free account can turn alerts on only for a fund
-- they have already opened (a report_views row). Paid accounts can alert
-- any fund. Visitors have no write grant. Bookmarks stay separate:
-- a watchlist row with alerts = false is still allowed.

alter table public.watchlist
  add column alerts boolean not null default false;

comment on column public.watchlist.alerts is
  'True when this saved fund should send alerts. Requires an opened report, or a paid account.';

create table public.fund_alert_settings (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  firm_id uuid not null references public.firms(id) on delete cascade,
  enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (profile_id, firm_id)
);

comment on table public.fund_alert_settings is
  'Per-fund alert switch. Insert and update require an opened report or a paid account.';

create index fund_alert_settings_firm_idx on public.fund_alert_settings (firm_id);

drop trigger if exists touch_fund_alert_settings on public.fund_alert_settings;
create trigger touch_fund_alert_settings
  before update on public.fund_alert_settings
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Who may turn alerts on
-- ---------------------------------------------------------------------------

create or replace function public.can_alert_fund(p_profile uuid, p_firm uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_profile is not null
    and p_firm is not null
    and (
      public.is_paid(p_profile)
      or exists (
        select 1
        from public.report_views v
        where v.profile_id = p_profile
          and v.firm_id = p_firm
      )
    );
$$;

create or replace function public.enforce_fund_alert()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  turning_on boolean;
begin
  if tg_table_name = 'watchlist' then
    turning_on := new.alerts;
  else
    turning_on := new.enabled;
  end if;
  if turning_on and not public.can_alert_fund(new.profile_id, new.firm_id) and not public.is_admin() then
    raise exception 'open this report to get alerts' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists watchlist_alert_guard on public.watchlist;
create trigger watchlist_alert_guard
  before insert or update on public.watchlist
  for each row execute function public.enforce_fund_alert();

drop trigger if exists fund_alert_settings_guard on public.fund_alert_settings;
create trigger fund_alert_settings_guard
  before insert or update on public.fund_alert_settings
  for each row execute function public.enforce_fund_alert();

-- ---------------------------------------------------------------------------
-- RLS. Global email prefs (alert_preferences) stay one row per account.
-- They have no firm, and signup inserts them before any report is opened.
-- ---------------------------------------------------------------------------

alter table public.fund_alert_settings enable row level security;

drop policy if exists watchlist_own on public.watchlist;

create policy watchlist_select on public.watchlist
  for select to authenticated
  using (profile_id = auth.uid() or public.is_admin());

create policy watchlist_insert on public.watchlist
  for insert to authenticated
  with check (
    public.is_admin()
    or (
      profile_id = auth.uid()
      and public.firm_is_public(firm_id)
      and (alerts = false or public.can_alert_fund(profile_id, firm_id))
    )
  );

create policy watchlist_update on public.watchlist
  for update to authenticated
  using (profile_id = auth.uid() or public.is_admin())
  with check (
    public.is_admin()
    or (
      profile_id = auth.uid()
      and public.firm_is_public(firm_id)
      and (alerts = false or public.can_alert_fund(profile_id, firm_id))
    )
  );

create policy watchlist_delete on public.watchlist
  for delete to authenticated
  using (profile_id = auth.uid() or public.is_admin());

create policy fund_alert_settings_select on public.fund_alert_settings
  for select to authenticated
  using (profile_id = auth.uid() or public.is_admin());

create policy fund_alert_settings_insert on public.fund_alert_settings
  for insert to authenticated
  with check (
    public.is_admin()
    or (
      profile_id = auth.uid()
      and public.can_alert_fund(profile_id, firm_id)
    )
  );

create policy fund_alert_settings_update on public.fund_alert_settings
  for update to authenticated
  using (profile_id = auth.uid() or public.is_admin())
  with check (
    public.is_admin()
    or (
      profile_id = auth.uid()
      and public.can_alert_fund(profile_id, firm_id)
    )
  );

create policy fund_alert_settings_delete on public.fund_alert_settings
  for delete to authenticated
  using (profile_id = auth.uid() or public.is_admin());

revoke all on table public.fund_alert_settings from public, anon;
grant select, insert, update, delete on table public.fund_alert_settings to authenticated;
grant all on table public.fund_alert_settings to service_role;

-- ---------------------------------------------------------------------------
-- Writers. Security definer bypasses RLS, so the same check lives here
-- and in the triggers above.
-- ---------------------------------------------------------------------------

create or replace function public.unwatch_fund(p_slug text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.fund_alert_settings s
  using public.firms f
  where s.firm_id = f.id
    and s.profile_id = auth.uid()
    and f.slug = p_slug;
  delete from public.watchlist w
  using public.firms f
  where w.firm_id = f.id
    and w.profile_id = auth.uid()
    and f.slug = p_slug;
end;
$$;

create or replace function public.set_fund_alert(p_slug text, p_on boolean)
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
    end if;
    insert into public.watchlist (profile_id, firm_id, alerts)
    values (uid, fid, true)
    on conflict (profile_id, firm_id) do update set alerts = true;
    insert into public.fund_alert_settings (profile_id, firm_id, enabled)
    values (uid, fid, true)
    on conflict (profile_id, firm_id) do update
      set enabled = true, updated_at = now();
    return jsonb_build_object('ok', true, 'on', true);
  end if;

  delete from public.fund_alert_settings
  where profile_id = uid and firm_id = fid;
  update public.watchlist
  set alerts = false
  where profile_id = uid and firm_id = fid;
  return jsonb_build_object('ok', true, 'on', false);
exception
  when check_violation then
    if sqlerrm ilike '%watchlist full%' then
      return jsonb_build_object('full', true);
    end if;
    return jsonb_build_object('ok', false, 'reason', 'unopened');
end;
$$;

create or replace function public.my_alert_funds()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(item order by item->>'name'), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'slug', f.slug,
      'name', f.name,
      'alerts', coalesce(w.alerts, false) or coalesce(s.enabled, false),
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
$$;

revoke all on function public.can_alert_fund(uuid, uuid) from public;
revoke all on function public.enforce_fund_alert() from public;
revoke all on function public.set_fund_alert(text, boolean) from public;
revoke all on function public.my_alert_funds() from public;

grant execute on function public.can_alert_fund(uuid, uuid) to authenticated, service_role;
grant execute on function public.set_fund_alert(text, boolean) to authenticated, service_role;
grant execute on function public.my_alert_funds() to authenticated, service_role;
