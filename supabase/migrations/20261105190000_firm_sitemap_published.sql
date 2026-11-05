-- sitemap.xml 500: the edge calls firm_sitemap with the anon key. anon lost EXECUTE, so the
-- worker threw and Cloudflare returned 1101. The function also still listed the old firms
-- table (thousands of slugs that have no page). A public page is a row in v2_firm_live,
-- the same set firm_meta serves. Without v2 (CI) the previous function stays.
do $m$
begin
  if to_regclass('public.v2_firm_live') is null or to_regclass('public.v2_firms') is null then
    raise notice 'v2 schema missing, firm_sitemap left as-is';
    return;
  end if;

  execute $fn$
    create or replace function public.firm_sitemap(p_page integer default 1, p_size integer default 10000)
    returns table (slug text, updated_at timestamptz, total bigint)
    language sql stable security definer set search_path = public, pg_temp
    as $body$
      with pub as (
        select l.slug::text as slug, l.live_since as updated_at
        from public.v2_firm_live l
        join public.v2_firms f on f.firm_id = l.firm_id
        where not coalesce(f.archived, false)
      )
      select p.slug, p.updated_at, (select count(*) from pub)
      from pub p
      order by p.slug
      offset greatest(coalesce(p_page, 1) - 1, 0) * least(greatest(coalesce(p_size, 10000), 1), 10000)
      limit least(greatest(coalesce(p_size, 10000), 1), 10000)
    $body$
  $fn$;

  revoke execute on function public.firm_sitemap(integer, integer) from public;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    grant execute on function public.firm_sitemap(integer, integer) to anon;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.firm_sitemap(integer, integer) to authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.firm_sitemap(integer, integer) to service_role;
  end if;
end $m$;
