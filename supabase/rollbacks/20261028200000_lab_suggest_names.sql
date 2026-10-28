-- Puts lab search back to matching every alias. Removes short-name aliases this step added.
-- Restores a row that was retyped. Does not delete legal or fund-entity aliases.

update public.firm_aliases a
set alias_type = g.old_type, source = g.old_source
from public.lab_short_name_log g
where g.action = 'retype' and a.firm_id = g.firm_id and lower(a.alias) = lower(g.alias);

delete from public.firm_aliases a
using public.lab_short_name_log g
where g.action = 'insert' and a.firm_id = g.firm_id and lower(a.alias) = lower(g.alias)
  and a.alias_type = 'short_name' and a.source = 'firm_site';

drop table if exists public.lab_short_name_log;
drop function if exists public.lab_short_name_aliases(boolean);

create or replace function public.firm_suggest(q text)
returns json language sql stable security definer set search_path = public as $$
  with t as (select lower(trim(q)) t), pub as (
    select f.* from firms f where f.published and not coalesce(f.is_test, false) and f.data_status = 'real' and f.deleted_at is null
  ), m as (
    select f.slug, coalesce(f.display_name, f.name) as name, f.short_name, f.hq, f.indexable,
      case when lower(coalesce(f.display_name, f.name)) like t || '%' or lower(coalesce(f.short_name, '')) like t || '%' or f.slug like t || '%' then 0
           when lower(coalesce(f.display_name, f.name)) ~ ('\m' || regexp_replace(t, '([^a-z0-9 ])', '\\\1', 'g')) then 1 else 2 end r
    from pub f, t
    where length(t) > 0
      and (lower(coalesce(f.display_name, f.name)) like '%' || t || '%' or lower(coalesce(f.short_name, '')) like '%' || t || '%' or f.slug like '%' || t || '%')
    union all
    select f.slug, coalesce(f.display_name, f.name), f.short_name, f.hq, f.indexable,
      case when lower(a.alias) like t || '%' then 0 when lower(a.alias) ~ ('\m' || regexp_replace(t, '([^a-z0-9 ])', '\\\1', 'g')) then 1 else 2 end
    from firm_aliases a join pub f on f.id = a.firm_id, t
    where length(t) > 0 and lower(a.alias) like '%' || t || '%'
  ), d as (select slug, name, short_name, hq, indexable, min(r) r from m group by slug, name, short_name, hq, indexable)
  select coalesce(json_agg(json_build_object('slug', slug, 'name', name, 'short_name', short_name, 'hq', hq) order by not indexable, r, name), '[]')
  from (select * from d order by not indexable, r, name limit 8) x
$$;

alter table public.firm_aliases drop constraint if exists firm_aliases_alias_type_chk;
alter table public.firm_aliases add constraint firm_aliases_alias_type_chk
  check (alias_type is null or alias_type in ('display', 'legal', 'fund_entity', 'old_name', 'website'));
