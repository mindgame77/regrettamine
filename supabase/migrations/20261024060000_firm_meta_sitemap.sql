-- Public, read-only lookups for the edge-rendered firm pages (Cloudflare Pages Function) and split sitemaps.
-- A firm has a public page when: published, real, not test, not deleted (launch_page no longer gates pages).
-- Only public fields are returned. SECURITY DEFINER with a fixed search_path; granted to anon explicitly.
create or replace function public.firm_meta(p_slug text)
returns table (slug text, name text, short_name text, hq text, firm_type text, legal_name text, primary_domain text, founded_year int, updated_at timestamptz)
language sql stable security definer set search_path = public, pg_temp as $$
  select f.slug, f.name, f.short_name, f.hq, f.firm_type, f.legal_name, f.primary_domain, f.founded_year::int, f.updated_at
  from public.firms f
  where f.slug = lower(p_slug) and f.published and not coalesce(f.is_test, false)
    and f.deleted_at is null and f.data_status = 'real'
  limit 1
$$;

create or replace function public.firm_sitemap(p_page int default 1, p_size int default 10000)
returns table (slug text, updated_at timestamptz, total bigint)
language sql stable security definer set search_path = public, pg_temp as $$
  with pub as (
    select f.slug, f.updated_at from public.firms f
    where f.published and not coalesce(f.is_test, false) and f.deleted_at is null and f.data_status = 'real'
  )
  select p.slug, p.updated_at, (select count(*) from pub) from pub p
  order by p.slug
  offset greatest(coalesce(p_page, 1) - 1, 0) * least(greatest(coalesce(p_size, 10000), 1), 10000)
  limit least(greatest(coalesce(p_size, 10000), 1), 10000)
$$;

revoke execute on function public.firm_meta(text) from public;
revoke execute on function public.firm_sitemap(int, int) from public;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    grant execute on function public.firm_meta(text) to anon;
    grant execute on function public.firm_sitemap(int, int) to anon;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.firm_meta(text) to authenticated;
    grant execute on function public.firm_sitemap(int, int) to authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.firm_meta(text) to service_role;
    grant execute on function public.firm_sitemap(int, int) to service_role;
  end if;
end $$;
