-- Speed: _firm_queue_id (used by firm_page, research_enrich, unlock_firm, ...) scanned all of
-- research_queue and recomputed the firm's name key for every row. Same matching rule and
-- same ordering; the firm's values are computed once and each OR arm can use an index.
-- Production: the index is built first with CREATE INDEX CONCURRENTLY (same name), so this is a no-op there.
create index if not exists research_queue_sec_crd_idx on public.research_queue (sec_crd);

create or replace function public._firm_queue_id(p_firm uuid)
 returns text
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  with f as (select registry_id, sec_crd, nullif(sec_crd, '') as sec, _queue_name_key(name) as nk
               from firms where id = p_firm)
  select coalesce((select registry_id from f),
   (select _registry_target(q.registry_id) from research_queue q, f
     -- = (nullif(sec,'') is not null and q.sec_crd = sec) or (length(coalesce(nk,'')) >= 4 and q.name_key = nk)
     where q.sec_crd = f.sec
        or q.name_key = case when length(coalesce(f.nk, '')) >= 4 then f.nk end
     order by coalesce(f.sec is not null and q.sec_crd = f.sec_crd, false) desc,
              (nullif(q.sec_crd, '') is not null) desc, q.priority, q.registry_id
     limit 1))
$function$;
