-- Search lists only firms with a live v2 page, and visitors can call it again.
-- old_db_off revoked execute on firm_suggest. The v2 switch gave firm_page and firm_meta
-- back to anon and did not give firm_suggest back, so the box showed "No results".
-- CI has no v2 tables, so the previous function stays and only the grant is applied.
do $mig$
begin
  if to_regclass('public.v2_firm_live') is not null and to_regclass('public.v2_firms') is not null then
    execute $fn$
create or replace function public.firm_suggest(q text)
returns json language sql stable security definer set search_path = public as $function$
  with t as (select lower(trim(q)) t), pub as (
    select f.slug::text as slug,
           f.display_name::text as name,
           f.short_name::text as short_name,
           nullif(concat_ws(', ', f.hq_city, coalesce(f.hq_state, f.hq_country)), '') as hq
    from public.v2_firm_live l
    join public.v2_firms f on f.firm_id = l.firm_id
    where not coalesce(f.archived, false)
  ), m as (
    select f.slug, f.name, f.short_name, f.hq,
      case when lower(coalesce(f.name, '')) like t || '%'
             or lower(coalesce(f.short_name, '')) like t || '%'
             or lower(f.slug) like t || '%' then 0
           when lower(coalesce(f.name, '')) ~ ('\m' || regexp_replace(t, '([^a-z0-9 ])', '\\\1', 'g')) then 1
           else 2 end r
    from pub f, t
    where length(t) > 0
      and (lower(coalesce(f.name, '')) like '%' || t || '%'
           or lower(coalesce(f.short_name, '')) like '%' || t || '%'
           or lower(f.slug) like '%' || t || '%')
  )
  select coalesce(json_agg(json_build_object('slug', slug, 'name', name, 'short_name', short_name, 'hq', hq) order by r, name), '[]')
  from (select * from m order by r, name limit 8) x
$function$
$fn$;
  else
    raise notice 'v2_firm_live missing, firm_suggest body unchanged';
  end if;

  if to_regprocedure('public.firm_suggest(text)') is not null then
    execute 'revoke all on function public.firm_suggest(text) from public';
    execute 'grant execute on function public.firm_suggest(text) to anon, authenticated, service_role';
  end if;
end
$mig$;
