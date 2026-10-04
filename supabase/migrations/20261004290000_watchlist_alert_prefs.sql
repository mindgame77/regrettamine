-- One pair of alert switches per account. They apply to every fund on the
-- watchlist the person is allowed to alert, including funds saved later.

update public.alert_preferences p
set new_legal_matter = exists (
      select 1 from public.fund_alert_settings s
      where s.profile_id = p.profile_id and s.new_legal_matter
    ),
    score_change = exists (
      select 1 from public.fund_alert_settings s
      where s.profile_id = p.profile_id and s.score_change
    ),
    updated_at = now()
where exists (
  select 1 from public.fund_alert_settings s
  where s.profile_id = p.profile_id
);

create or replace function public.sync_watch_alerts(p_uid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  legal boolean;
  score boolean;
  row record;
begin
  if p_uid is null then
    return;
  end if;
  select a.new_legal_matter, a.score_change
    into legal, score
  from public.alert_preferences a
  where a.profile_id = p_uid;
  legal := coalesce(legal, false);
  score := coalesce(score, false);

  for row in
    select w.firm_id
    from public.watchlist w
    where w.profile_id = p_uid
  loop
    if (legal or score) and public.can_alert_fund(p_uid, row.firm_id) then
      insert into public.fund_alert_settings (
        profile_id, firm_id, enabled, new_legal_matter, score_change
      ) values (
        p_uid, row.firm_id, true, legal, score
      )
      on conflict (profile_id, firm_id) do update
        set enabled = true,
            new_legal_matter = excluded.new_legal_matter,
            score_change = excluded.score_change,
            updated_at = now();
      update public.watchlist
      set alerts = true
      where profile_id = p_uid and firm_id = row.firm_id;
    else
      delete from public.fund_alert_settings
      where profile_id = p_uid and firm_id = row.firm_id;
      update public.watchlist
      set alerts = false
      where profile_id = p_uid and firm_id = row.firm_id;
    end if;
  end loop;
end;
$$;

create or replace function public.sync_watch_alerts_from_view()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.profile_id is not null then
    perform public.sync_watch_alerts(new.profile_id);
  end if;
  return new;
end;
$$;

drop trigger if exists report_views_sync_watch_alerts on public.report_views;
create trigger report_views_sync_watch_alerts
  after insert on public.report_views
  for each row execute function public.sync_watch_alerts_from_view();

create or replace function public.set_watch_alert_kind(p_kind text, p_on boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  legal boolean;
  score boolean;
begin
  if uid is null then
    return jsonb_build_object('needAuth', true);
  end if;
  if p_kind not in ('new_legal_matter', 'score_change') then
    return jsonb_build_object('ok', false, 'reason', 'missing');
  end if;
  insert into public.alert_preferences (profile_id)
  values (uid)
  on conflict (profile_id) do nothing;
  if p_kind = 'new_legal_matter' then
    update public.alert_preferences
    set new_legal_matter = coalesce(p_on, false), updated_at = now()
    where profile_id = uid;
  else
    update public.alert_preferences
    set score_change = coalesce(p_on, false), updated_at = now()
    where profile_id = uid;
  end if;
  perform public.sync_watch_alerts(uid);
  select a.new_legal_matter, a.score_change into legal, score
  from public.alert_preferences a
  where a.profile_id = uid;
  return jsonb_build_object(
    'ok', true,
    'new_legal_matter', legal,
    'score_change', score
  );
end;
$$;

create or replace function public.my_watch_alerts()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'new_legal_matter', coalesce(a.new_legal_matter, false),
    'score_change', coalesce(a.score_change, false)
  )
  from public.alert_preferences a
  where a.profile_id = auth.uid();
$$;

create or replace function public.set_fund_alert_kind(
  p_slug text,
  p_kind text,
  p_on boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  fid uuid;
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
  if fid is null or not exists (
    select 1 from public.watchlist where profile_id = uid and firm_id = fid
  ) then
    return jsonb_build_object('ok', false, 'reason', 'missing');
  end if;
  if coalesce(p_on, false) and not public.can_alert_fund(uid, fid) then
    return jsonb_build_object('ok', false, 'reason', 'unopened');
  end if;
  return public.set_watch_alert_kind(p_kind, p_on);
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
    perform public.sync_watch_alerts(uid);
    return jsonb_build_object('saved', true);
  end if;
  select count(*) into n from public.watchlist where profile_id = uid;
  if n >= 100 then
    return jsonb_build_object('full', true);
  end if;
  insert into public.watchlist (profile_id, firm_id) values (uid, fid);
  perform public.sync_watch_alerts(uid);
  return jsonb_build_object('saved', true);
exception
  when check_violation then
    return jsonb_build_object('full', true);
end;
$$;

revoke all on function public.sync_watch_alerts(uuid) from public;
revoke all on function public.sync_watch_alerts_from_view() from public;
revoke all on function public.set_watch_alert_kind(text, boolean) from public;
revoke all on function public.my_watch_alerts() from public;
grant execute on function public.sync_watch_alerts(uuid) to service_role;
grant execute on function public.set_watch_alert_kind(text, boolean) to authenticated, service_role;
grant execute on function public.my_watch_alerts() to authenticated, service_role;

select public.sync_watch_alerts(p.profile_id)
from public.alert_preferences p;
