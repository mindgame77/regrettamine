-- Removes the aliases this step added. Does not remove older aliases.

delete from public.firm_aliases a
using public.lab_search_alias_log g
where a.firm_id = g.firm_id and lower(a.alias) = lower(g.alias);

drop table if exists public.lab_search_alias_log;

drop function if exists public.lab_check_search_names(uuid, int);
drop function if exists public.lab_search_aliases(boolean);

alter table public.firm_aliases drop constraint if exists firm_aliases_alias_type_chk;
alter table public.firm_aliases add constraint firm_aliases_alias_type_chk
  check (alias_type is null or alias_type in ('display', 'legal', 'fund_entity', 'old_name'));

alter table public.firm_aliases drop constraint if exists firm_aliases_source_check;
alter table public.firm_aliases add constraint firm_aliases_source_check
  check (source in ('sec_legal', 'previous_display', 'queue_name', 'merged'));
