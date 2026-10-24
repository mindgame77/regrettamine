-- search_log keeps rows from superseded enrichments (nothing is deleted). Views now read only
-- current rows: enrichment_id is null (submissions / manual) or it is the latest valid enrichment
-- for that firm+bot, same order as promote_enrichment (received_at desc, id desc).
create or replace view public.search_log_current with (security_invoker = true) as
  select l.*
  from search_log l
  where l.enrichment_id is null
     or l.enrichment_id = (select e2.id from research_enrichments e
                             join research_enrichments e2 on e2.valid and e2.bot_id = e.bot_id
                              and coalesce(e2.firm_id::text, e2.registry_id) = coalesce(e.firm_id::text, e.registry_id)
                            where e.id = l.enrichment_id
                            order by e2.received_at desc, e2.id desc limit 1);
revoke all on public.search_log_current from anon, authenticated, public;

create or replace view public.firm_site_coverage as
  select coalesce(f.slug, l.registry_id) firm, l.firm_id, l.registry_id, l.section, l.source_site,
    count(*) searches, count(*) filter (where result = 'found') found, count(*) filter (where result = 'none') none,
    count(*) filter (where result = 'blocked') blocked, count(*) filter (where result = 'error') error,
    sum(item_count) items, max(searched_at) last_searched
  from search_log_current l left join firms f on f.id = l.firm_id
  group by 1, 2, 3, 4, 5;
create or replace view public.site_search_stats as
  select source_site, count(*) searches, count(distinct coalesce(firm_id::text, registry_id)) firms,
    round(avg((result = 'found')::int), 3) found_rate, round(avg((result = 'none')::int), 3) none_rate,
    round(avg((result = 'blocked')::int), 3) blocked_rate, round(avg((result = 'error')::int), 3) error_rate
  from search_log_current group by 1;
revoke all on public.firm_site_coverage, public.site_search_stats from anon, authenticated, public;

create or replace view public.firm_section_status as
with fq as (
  select f.id firm_id, f.slug, f.name, f.published, _firm_queue_id(f.id) registry_id from firms f
   where f.deleted_at is null and not coalesce(f.is_test, false) and (f.published or f.launch_page)

  -- queued = firms on the publish queue (launch_page). The 7k-row research registry is not a page queue and is left out.
), base as (
  select fq.*, s.sec,
    case when fq.firm_id is null then false
         when s.sec = 'checks' then exists (select 1 from firm_check_rows c where c.firm_id = fq.firm_id and c.source_submission is not null)
         when s.sec = 'board_seats' then exists (select 1 from firm_people_roles p where p.firm_id = fq.firm_id and p.kind = 'board'
                                                  and exists (select 1 from fact_sources x where x.fact_type = 'firm_people_roles' and x.fact_id = p.id))
         else jsonb_array_length(_sec_items(s.sec, fq.firm_id)) > 0 end filled
  from fq cross join (values ('overview'), ('checks'), ('legal'), ('people'), ('board_seats'), ('funds'), ('timeline'), ('press'), ('founders')) s(sec)
), sec as (
  select b.firm_id, b.slug, b.name, b.published, b.registry_id, b.sec item,
    case when b.filled then 'filled'
         when exists (select 1 from search_log_current l where l.section = b.sec and l.result = 'none' and l.searched_at is not null
                        and (l.firm_id = b.firm_id or l.registry_id = b.registry_id)) then 'searched_none'
         else 'missing' end status,
    (select max(searched_at) from search_log_current l where l.section = b.sec and (l.firm_id = b.firm_id or l.registry_id = b.registry_id)) last_searched
  from base b
), chk as (
  select distinct fq.firm_id, fq.slug, fq.name, fq.published, fq.registry_id, 'checklist:' || (c->>'checklist_item') item,
    case when c->>'status' = 'blocked' then 'blocked' else 'not_searched' end status, null::timestamptz last_searched
  from fq join lateral (select payload from research_submissions s where s.registry_id = fq.registry_id and s.valid order by received_at desc, id desc limit 1) ls on true,
       jsonb_array_elements(coalesce(ls.payload->'coverage', '[]')) c
  where c->>'status' in ('blocked', 'not_searched')
), allx as (select * from sec union all select * from chk)
select a.*, count(*) filter (where status in ('filled', 'searched_none')) over w done,
  count(*) over w total,
  round(count(*) filter (where status in ('filled', 'searched_none')) over w::numeric / count(*) over w, 3) score
from allx a window w as (partition by coalesce(a.firm_id::text, a.registry_id));
revoke all on public.firm_section_status from anon, authenticated, public;
