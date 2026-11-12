-- Restores _v2_deals to the parent-name sector field only.
create or replace function public._v2_deals(fid bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  select coalesce(jsonb_agg(x order by x->>'date' desc nulls last, x->>'company'),'[]') from (
    select jsonb_build_object('company',s.startup_name,'round',d.round,'date',d.deal_date::text,'date_precision',coalesce(d.deal_date_precision,'day'),
      'url',d.source_url,'amount',d.round_amount,'currency',d.amount_currency,'lead',coalesce(d.lead='yes',false),
      'sector',(select sc.name from v2_startup_sectors ss join v2_sector sc on sc.sector_id=ss.sector_id where ss.startup_id=s.startup_id and ss.is_current and not ss.archived limit 1),
      'domain',s.domain,'website_url',s.website_url) x
    from v2_deals d join v2_startups s on s.startup_id=d.startup_id and s.is_current and not s.archived
    where d.firm_id=fid and d.is_current and not d.archived and coalesce(d.shown,true) and not d.nothing_found) q
$$;
