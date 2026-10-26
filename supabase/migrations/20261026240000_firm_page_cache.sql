-- Ready-made firm_details, one row per firm.
-- firm_page_cache stores the full payload. A missing row is stale.
-- unlock_firm (and so firm_page) reads it when present, and builds it live then stores it when missing.
-- Publish, enricher writes, and fact or legal edits only delete that row. The trigger does not rebuild.
-- Who can open the page stays in unlock_firm. The cache is never a locked or per-user copy.

create table public.firm_page_cache (
  firm_id uuid primary key references public.firms(id) on delete cascade,
  payload jsonb not null,
  built_at timestamptz not null default now()
);

alter table public.firm_page_cache enable row level security;
revoke all on table public.firm_page_cache from public, anon, authenticated;

create or replace function public._firm_page_cache_invalidate() returns trigger
language plpgsql security definer set search_path = public as $$
declare fid uuid;
begin
  if tg_op = 'DELETE' then
    fid := old.firm_id;
  else
    fid := new.firm_id;
    if tg_op = 'UPDATE' and old.firm_id is distinct from new.firm_id then
      delete from public.firm_page_cache where firm_id = old.firm_id;
    end if;
  end if;
  if fid is not null then
    delete from public.firm_page_cache where firm_id = fid;
  end if;
  if tg_op = 'DELETE' then return old; else return new; end if;
end $$;

-- Page tables a publish, an enricher write, or a fact / legal edit touches, plus the rows firm_details reads.
do $$
declare t text;
begin
  foreach t in array array[
    'firm_profile_facts', 'firm_legal_items', 'fact_sources', 'vc_source_facts',
    'firm_people_roles', 'timeline_events', 'press_item_firms', 'reviews', 'firm_check_rows'
  ]
  loop
    execute format(
      'create trigger firm_page_cache_inv after insert or update or delete on public.%I
         for each row execute function public._firm_page_cache_invalidate()', t);
  end loop;
end $$;

create or replace function public._firm_details_cached(p_firm uuid) returns json
language plpgsql security definer set search_path = public as $$
declare p jsonb;
begin
  select payload into p from public.firm_page_cache where firm_id = p_firm;
  if found then
    return p::json;
  end if;
  p := coalesce(public.firm_details(p_firm)::jsonb, '[]'::jsonb);
  insert into public.firm_page_cache(firm_id, payload, built_at)
  values (p_firm, p, now())
  on conflict (firm_id) do update set payload = excluded.payload, built_at = excluded.built_at;
  return p::json;
end $$;

-- At most p_limit firms that have no cache row. Call again after a pause to warm the rest.
create or replace function public.warm_firm_page_cache(p_limit int default 20) returns int
language plpgsql security definer set search_path = public as $$
declare n int := 0; r record;
begin
  for r in
    select f.id from public.firms f
    left join public.firm_page_cache c on c.firm_id = f.id
    where f.deleted_at is null and f.published and not coalesce(f.is_test, false) and f.data_status = 'real'
      and c.firm_id is null
    order by f.slug
    limit greatest(coalesce(p_limit, 20), 0)
  loop
    perform public._firm_details_cached(r.id);
    n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.unlock_firm(p_slug text, p_anon uuid, p_spend boolean default true, p_email text default null)
returns json language plpgsql security definer set search_path = public as $$
declare b public.check_balances := _balance(p_anon); f uuid; ix boolean; h text := _ip_hash(); ip_cap constant int := 4;
  need boolean; qid text; sk text; em text;
begin
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

revoke all on function public._firm_page_cache_invalidate() from public, anon, authenticated;
grant execute on function public._firm_page_cache_invalidate() to service_role;
revoke all on function public._firm_details_cached(uuid) from public, anon, authenticated;
revoke all on function public.warm_firm_page_cache(int) from public, anon, authenticated;
revoke all on function public.unlock_firm(text, uuid, boolean, text) from public, anon, authenticated;
grant execute on function public._firm_details_cached(uuid), public.warm_firm_page_cache(int),
  public.unlock_firm(text, uuid, boolean, text) to service_role;

-- Two known pages first. The rest is warm_firm_page_cache, in small batches.
select public._firm_details_cached(id) from public.firms
 where slug in ('y-combinator', 'a16z') and deleted_at is null;
