-- Backfill: a page for every registry entry with a valid research report, then link orphan enrichments and
-- search_log rows by registry_id (rows are linked, never copied: re-sent enrichments do not duplicate items).
-- Idempotent; on a fresh database it does nothing.
do $$
declare r record;
begin
  for r in select distinct _registry_target(s.registry_id) rid from research_submissions s
           join research_queue q on q.registry_id = s.registry_id where s.valid order by 1 loop
    perform ensure_firm_for_registry(r.rid, true);
  end loop;
end $$;

update research_enrichments e set firm_id = f.id
from firms f where e.firm_id is null and e.registry_id is not null and f.deleted_at is null and f.registry_id = _registry_target(e.registry_id);

update search_log l set firm_id = f.id
from research_queue q, firms f
where l.firm_id is null and l.registry_id = q.registry_id and f.deleted_at is null and f.registry_id = coalesce(q.duplicate_of, q.registry_id);

do $$
declare r record;
begin
  for r in select distinct firm_id from research_enrichments where firm_id is not null and valid loop
    perform promote_enrichment(r.firm_id);
  end loop;
end $$;
