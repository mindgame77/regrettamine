-- Undo B. Restores claim order, live-on-insert, the public firm reads, and the old outbox.
-- Drops the matcher, the wanted list, and the priority column. Search log and watches stay
-- until 20261112180000 is undone. Run this before that undo.
do $mig$
declare
  def text;
  fn text;
begin
  if to_regclass('cron.job') is not null then
    if exists (select 1 from cron.job where jobname = 'v2-search-demand') then
      perform cron.unschedule('v2-search-demand');
    end if;
  end if;

  if to_regclass('public.v2_research_assignments') is not null then
    execute 'drop trigger if exists v2_research_done_go_live on public.v2_research_assignments';
  end if;

  if to_regprocedure('public.v2_research_claim(uuid)') is not null then
    select pg_get_functiondef('public.v2_research_claim(uuid)'::regprocedure) into def;
    def := replace(def, 'ORDER BY CASE q.priority WHEN ''top'' THEN 0 ELSE 1 END, q.firm_id', 'ORDER BY q.firm_id');
    execute def;
  end if;

  if to_regclass('public.v2_firms') is not null and to_regclass('public.v2_firm_live') is not null then
    execute $live$
create or replace function public.v2_firm_live_on_insert()
returns trigger
language plpgsql
security definer
set search_path to public
as $body$
begin
  if nullif(btrim(new.slug::text), '') is null then
    return new;
  end if;
  insert into public.v2_firm_live (firm_id, slug)
  values (new.firm_id, lower(btrim(new.slug::text)))
  on conflict (firm_id) do nothing;
  return new;
end
$body$
$live$;
  end if;

  foreach fn in array array['_v2_live_id(text)', 'firm_meta(text)', 'firm_sitemap(integer,integer)', 'firm_suggest(text)', 'firm_directory()'] loop
    if to_regprocedure('public.' || fn) is not null then
      execute format('select pg_get_functiondef(%L::regprocedure)', 'public.' || fn) into def;
      def := replace(def, 'and not coalesce(f.demand_hidden, false)', '');
      execute def;
    end if;
  end loop;

  if to_regclass('public.research_requests') is not null and to_regclass('public.firm_request_emails') is not null then
    execute $box$
create or replace function public.ondemand_outbox(p_limit int default 50)
returns table(id bigint, kind text, email text, name text, slug text)
language sql stable security definer set search_path = public as $body$
  select * from (
    select r.id,
           case when r.status = 'refunded' then 'refund'
                when r.spend_kind = 'request' and r.firm_request_id is not null then 'ready_request'
                else 'ready' end kind,
           r.email, coalesce(f.display_name, f.name) name, f.slug
      from research_requests r join firms f on f.id = r.firm_id
     where r.status in ('done', 'refunded') and r.email is not null and r.notified_at is null and r.notify_error is null
       and f.published and f.deleted_at is null and f.data_status = 'real' and not coalesce(f.is_test, false)
    union all
    select e.id, 'received', e.email, q.name, null::text
      from firm_request_emails e join firm_requests q on q.id = e.request_id
     where e.received_notified_at is null and e.notify_error is null and e.research_request_id is null
       and e.created_at > now() - interval '2 days') x
  order by kind = 'received', id limit greatest(1, least(coalesce(p_limit, 50), 200))
$body$
$box$;
    execute $mark$
create or replace function public.ondemand_mark_notified(p_id bigint, p_error text default null, p_kind text default null) returns void
language plpgsql security definer set search_path = public as $body$
begin
  if p_kind = 'received' then
    update firm_request_emails set received_notified_at = case when p_error is null then now() end, notify_error = left(p_error, 500) where id = p_id;
  else
    update research_requests set notified_at = case when p_error is null then now() end, notify_error = left(p_error, 500) where id = p_id;
    update check_requests set notified_at = coalesce(notified_at, case when p_error is null then now() end),
      status = case when p_error is null then 'done' else status end
     where research_request_id = p_id;
  end if;
end
$body$
$mark$;
  end if;

  execute 'drop function if exists public.v2_search_demand_run()';
  execute 'drop function if exists public.v2_search_demand_one(text)';
  execute 'drop function if exists public.v2_search_attach(bigint, text, text, text)';
  execute 'drop function if exists public.v2_search_wanted_note(text, text)';
  execute 'drop function if exists public.v2_research_done_go_live()';
  execute 'drop function if exists public.v2_search_go_live(bigint)';
  execute 'drop table if exists public.v2_search_wanted';
  execute 'drop table if exists public.v2_search_demand_cursor';
  execute 'drop index if exists public.research_queue_name_exact_idx';
  execute 'drop index if exists public.research_queue_website_domain_idx';
  execute 'drop index if exists public.v2_research_assignments_priority_open';
  if to_regclass('public.v2_research_assignments') is not null
     and exists (
       select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'v2_research_assignments' and column_name = 'priority'
     ) then
    execute 'alter table public.v2_research_assignments drop constraint if exists v2_research_assignments_priority_ck';
    execute 'alter table public.v2_research_assignments drop column priority';
  end if;
end
$mig$;
