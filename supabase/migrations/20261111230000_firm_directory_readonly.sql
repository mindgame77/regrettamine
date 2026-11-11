-- CI has no v2 tables, so the function is created only where they exist.
do $mig$
begin
  if to_regclass('public.v2_auto_published') is not null and to_regclass('public.v2_deals') is not null and to_regclass('public.v2_firm_industries') is not null and to_regclass('public.v2_firm_live') is not null and to_regclass('public.v2_firm_stages') is not null and to_regclass('public.v2_firms') is not null and to_regclass('public.v2_legal_items') is not null and to_regclass('public.v2_sector') is not null and to_regclass('public.v2_startup_sectors') is not null and to_regclass('public.v2_startups') is not null then
    execute $fn$
create or replace function public.firm_directory()
returns json
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  with live as (
    select f.firm_id, l.slug, l.live_since, f.display_name, f.short_name, f.website_url,
           f.hq_city, f.hq_state, upper(btrim(f.hq_country)) as hq_country, coalesce(nullif(f.firm_status,''),'Active') as firm_status
      from v2_firm_live l join v2_firms f on f.firm_id = l.firm_id
     where not coalesce(f.archived,false) and f.merged_into_firm_id is null
  ),
  d as (
    select d.firm_id, s.startup_id, s.startup_name, s.domain, d.round, d.deal_date, coalesce(d.lead='yes',false) as led
      from v2_deals d join v2_startups s on s.startup_id = d.startup_id and s.is_current and not s.archived
     where d.firm_id in (select firm_id from live) and d.is_current and not d.archived
       and coalesce(d.shown,true) and not d.nothing_found and d.deal_date is not null
  ),
  dagg as (
    select firm_id, count(*) as deals,
           count(*) filter (where deal_date >= current_date - 365) as deals_12m,
           count(*) filter (where deal_date >= current_date - 365 and led) as led_12m,
           array_agg(distinct startup_name) filter (where startup_name is not null) as startups,
           array_agg(distinct domain) filter (where nullif(domain,'') is not null) as startup_sites
      from d group by firm_id
  ),
  latest as (
    select distinct on (firm_id) firm_id, startup_name, round, deal_date
      from d order by firm_id, deal_date desc, startup_name
  ),
  inds as (
    select i.firm_id, json_agg(i.industry_text order by i.position, i.id) as industries
      from v2_firm_industries i
     where i.firm_id in (select firm_id from live) and i.is_current and not i.archived and nullif(btrim(i.industry_text),'') is not null
     group by i.firm_id
  ),
  dsec as (
    select firm_id, json_agg(name order by n desc, name) as industries from (
      select d.firm_id, sc.name, count(*) n
        from d join v2_startup_sectors ss on ss.startup_id = d.startup_id and ss.is_current and not ss.archived
        join v2_sector sc on sc.sector_id = ss.sector_id
       group by 1,2) x group by firm_id
  ),
  stg as (
    select firm_id, json_agg(distinct stage) as stages
      from v2_firm_stages where firm_id in (select firm_id from live) and is_current and not archived and nullif(btrim(stage),'') is not null
     group by firm_id
  ),
  leg as (
    select firm_id, count(*) as n from v2_legal_items
     where firm_id in (select firm_id from live) and is_current and not archived and not nothing_found and not coalesce(lead_only,false)
     group by firm_id
  ),
  pub as (
    select firm_id, max(applied_at) as last_fact
      from v2_auto_published
     where firm_id in (select firm_id from live)
     group by firm_id
  )
  select coalesce(json_agg(json_build_object(
      'slug', l.slug, 'name', l.display_name, 'short_name', nullif(l.short_name,''), 'website', l.website_url,
      'city', l.hq_city, 'state', l.hq_state, 'country', case when l.hq_country ~ '^[A-Z]{2}$' then l.hq_country end,
      'added', coalesce(p.last_fact, l.live_since), 'firm_status', l.firm_status,
      'industries', coalesce(i.industries, ds.industries, '[]'::json),
      'stages', coalesce(st.stages, '[]'::json),
      'deals', coalesce(a.deals,0), 'deals_12m', coalesce(a.deals_12m,0), 'led_12m', coalesce(a.led_12m,0),
      'latest_company', lt.startup_name, 'latest_round', lt.round, 'latest_deal_date', lt.deal_date,
      'legal_records', coalesce(lg.n,0), 'legal_status', case when lg.n > 0 then 'has' else 'unknown' end,
      'startups', coalesce(to_json(a.startups), '[]'::json), 'startup_sites', coalesce(to_json(a.startup_sites), '[]'::json)
    ) order by coalesce(p.last_fact, l.live_since) desc, l.display_name), '[]'::json)
    from live l
    left join dagg a on a.firm_id = l.firm_id
    left join latest lt on lt.firm_id = l.firm_id
    left join inds i on i.firm_id = l.firm_id
    left join dsec ds on ds.firm_id = l.firm_id
    left join stg st on st.firm_id = l.firm_id
    left join leg lg on lg.firm_id = l.firm_id
    left join pub p on p.firm_id = l.firm_id
$$
$fn$;
    execute 'revoke all on function public.firm_directory() from public';
    execute 'grant execute on function public.firm_directory() to anon, authenticated';
  end if;
end
$mig$;
