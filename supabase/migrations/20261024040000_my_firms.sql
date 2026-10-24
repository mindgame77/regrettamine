-- My firms page + Save on every firm page. NOT YET APPLIED: waiting for Alex's approval.
-- 1) Guard (no backup table): watchlist was 0 rows on 2026-10-23. Abort if that is no longer true.
do $$ begin
  if (select count(*) from public.watchlist) > 0 then
    raise exception 'my_firms migration aborted: public.watchlist has % rows (expected 0)', (select count(*) from public.watchlist);
  end if;
end $$;

-- 2) watch_fund: any published / launch firm can be saved, checked or not (was: only firms in my_checks).
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
  insert into public.watchlist (profile_id, firm_id) values (uid, fid) on conflict do nothing;
  perform public.sync_watch_alerts(uid);
  return jsonb_build_object('saved', true);
end;
$$;

-- 3) my_firms(): every firm the user checked or saved, newest activity first. Result counts use the check page's
-- display labels from firm_check_rows: Clear = clear/nf, Review = review/red, Worth knowing = wk (Not checked yet not counted).
create or replace function public.my_firms()
returns json language sql stable security definer set search_path to 'public' as $$
  with ch as (select ce.firm_id, min(ce.created_at) at from check_events ce join check_balances b on b.id = ce.balance_id
              where b.user_id = auth.uid() and ce.kind like 'spend_%' and ce.firm_id is not null group by ce.firm_id),
       sv as (select firm_id, created_at at from watchlist where profile_id = auth.uid()),
       ids as (select firm_id from ch union select firm_id from sv)
  select coalesce(json_agg(json_build_object('slug', f.slug, 'name', f.name, 'short_name', f.short_name, 'hq', f.hq,
    'checked_at', ch.at, 'saved', sv.at is not null, 'saved_at', sv.at,
    'clear', r.clear, 'review', r.review, 'wk', r.wk) order by greatest(ch.at, sv.at) desc), '[]'::json)
  from ids join firms f on f.id = ids.firm_id
  left join ch on ch.firm_id = f.id left join sv on sv.firm_id = f.id
  cross join lateral (select count(*) filter (where state in ('clear', 'nf')) clear, count(*) filter (where state in ('review', 'red')) review,
                             count(*) filter (where state = 'wk') wk from firm_check_rows where firm_id = f.id) r
  where auth.uid() is not null
$$;
revoke all on function public.my_firms() from public, anon;
grant execute on function public.my_firms() to authenticated;
