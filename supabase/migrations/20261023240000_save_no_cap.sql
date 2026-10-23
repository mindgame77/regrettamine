-- Save (watchlist) on launch firm pages: no 100-firm cap; only firms the signed-in user has already checked;
-- my_checks() also returns saved_at for the account Saved list. Backup: _bak_watchlist_20261023 (0 rows).
drop trigger if exists watchlist_cap on public.watchlist;
drop function if exists public.watchlist_cap();

create or replace function public.watch_fund(p_slug text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  uid uuid := auth.uid();
  fid uuid;
begin
  if uid is null then
    return jsonb_build_object('needAuth', true);
  end if;
  select id into fid from public.firms where slug = p_slug and (published or launch_page) and not is_test;
  if fid is null then
    return jsonb_build_object('error', 'That fund is not in the database yet.');
  end if;
  if not exists (select 1 from public.check_events ce join public.check_balances b on b.id = ce.balance_id
                 where b.user_id = uid and ce.firm_id = fid and ce.kind like 'spend_%') then
    return jsonb_build_object('error', 'Check this firm first to save it.');
  end if;
  insert into public.watchlist (profile_id, firm_id) values (uid, fid) on conflict do nothing;
  perform public.sync_watch_alerts(uid);
  return jsonb_build_object('saved', true);
end;
$$;

create or replace function public.my_checks()
returns json language sql stable security definer set search_path to 'public' as $$
  select coalesce(json_agg(json_build_object('slug', f.slug, 'name', f.name, 'short_name', f.short_name,
    'checked_at', e.at, 'active', c.active, 'cases', c.cases,
    'saved', w.created_at is not null, 'saved_at', w.created_at) order by e.at desc), '[]'::json)
  from (select ce.firm_id, min(ce.created_at) at from check_events ce join check_balances b on b.id = ce.balance_id
        where b.user_id = auth.uid() and ce.kind like 'spend_%' and ce.firm_id is not null group by ce.firm_id) e
  join firms f on f.id = e.firm_id
  left join watchlist w on w.profile_id = auth.uid() and w.firm_id = f.id
  cross join lateral (select count(*) filter (where status = 'active') active, count(*) filter (where status is not null) cases
                      from public._firm_cases(f.id) where is_case and party and rn <> 9) c
  where auth.uid() is not null
$$;
