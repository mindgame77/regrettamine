-- Undo A. Drops the search-demand tables, RPCs and the hidden flag.
-- Does not touch v2 firm rows other than dropping demand_hidden.
do $mig$
begin
  if to_regprocedure('public.v2_log_search(text, text, integer, text, uuid)') is not null then
    execute 'drop function public.v2_log_search(text, text, integer, text, uuid)';
  end if;
  if to_regprocedure('public.v2_watch_firm(text, text, uuid)') is not null then
    execute 'drop function public.v2_watch_firm(text, text, uuid)';
  end if;
  if to_regprocedure('public.v2_search_norm(text)') is not null then
    execute 'drop function public.v2_search_norm(text)';
  end if;
  execute 'drop table if exists public.v2_firm_watch';
  execute 'drop table if exists public.v2_search_log';
  if to_regclass('public.v2_firms') is not null
     and exists (
       select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'v2_firms' and column_name = 'demand_hidden'
     ) then
    execute 'alter table public.v2_firms drop column demand_hidden';
  end if;
end
$mig$;
