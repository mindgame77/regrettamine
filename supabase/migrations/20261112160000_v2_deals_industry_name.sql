-- Page read only. Each deal keeps sector as the parent industry (v2_sector.name)
-- and adds industry_name from the same startup tag. A null industry_name stays null
-- so the page can fall back to the parent. Stored rows are not rewritten.
do $mig$
begin
  if to_regprocedure('public._v2_deals(bigint)') is not null
     and to_regclass('public.v2_deals') is not null
     and to_regclass('public.v2_startups') is not null
     and to_regclass('public.v2_startup_sectors') is not null
     and to_regclass('public.v2_sector') is not null
     and exists (
       select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'v2_startup_sectors' and column_name = 'industry_name'
     ) then
    execute $fn$
create or replace function public._v2_deals(fid bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  select coalesce(jsonb_agg(x order by x->>'date' desc nulls last, x->>'company'),'[]') from (
    select jsonb_build_object(
      'company', s.startup_name,
      'round', d.round,
      'date', d.deal_date::text,
      'date_precision', coalesce(d.deal_date_precision, 'day'),
      'url', d.source_url,
      'amount', d.round_amount,
      'currency', d.amount_currency,
      'lead', coalesce(d.lead = 'yes', false),
      'sector', sec.name,
      'industry_name', sec.industry_name,
      'domain', s.domain,
      'website_url', s.website_url) x
    from v2_deals d
    join v2_startups s on s.startup_id = d.startup_id and s.is_current and not s.archived
    left join lateral (
      select sc.name, nullif(btrim(ss.industry_name), '') as industry_name
      from v2_startup_sectors ss
      join v2_sector sc on sc.sector_id = ss.sector_id
      where ss.startup_id = s.startup_id and ss.is_current and not ss.archived
      limit 1
    ) sec on true
    where d.firm_id = fid and d.is_current and not d.archived and coalesce(d.shown, true) and not d.nothing_found
  ) q
$$
$fn$;
  end if;
end
$mig$;
