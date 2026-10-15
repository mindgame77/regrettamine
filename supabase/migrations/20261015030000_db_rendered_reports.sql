-- Every VC page renders from the database through one path (Alex, Oct 14, 2026).
-- 1. The site bundle also carries the real rows of the research tables.
-- 2. A public bundle gives the static build what a visitor may see (list rows,
--    stats, updates, shared fragments) without report bodies.
-- 3. site_fragments holds rendered shared pieces (the scoring example), written
--    by the service-side publish step.

alter function public.published_site_bundle() rename to published_site_core;
revoke all on function public.published_site_core() from public, anon, authenticated;
grant execute on function public.published_site_core() to service_role;

create or replace function public.published_site_bundle()
returns jsonb
language sql
stable security definer
set search_path = public
as $$
  with pub as (
    select id, slug from firms where published and not is_test
  )
  select public.published_site_core() || jsonb_build_object(
    'vc_source_facts', coalesce((select jsonb_agg(to_jsonb(t) || jsonb_build_object('slug', p.slug) order by p.slug, t.section, t.created_at, t.id)
      from vc_source_facts t join pub p on p.id = t.firm_id where t.data_status = 'real' and t.superseded_by is null), '[]'::jsonb),
    'vc_entity_identifiers', coalesce((select jsonb_agg(to_jsonb(t) || jsonb_build_object('slug', p.slug) order by p.slug, t.id_type, t.value)
      from vc_entity_identifiers t join pub p on p.id = t.firm_id where t.data_status = 'real'), '[]'::jsonb),
    'vc_partner_history', coalesce((select jsonb_agg(to_jsonb(t) || jsonb_build_object('slug', p.slug) order by p.slug, t.person_name, t.id)
      from vc_partner_history t join pub p on p.id = t.firm_id where t.data_status = 'real'), '[]'::jsonb),
    'vc_political_activity', coalesce((select jsonb_agg(to_jsonb(t) || jsonb_build_object('slug', p.slug) order by p.slug, t.person_name, t.id)
      from vc_political_activity t join pub p on p.id = t.firm_id where t.data_status = 'real'), '[]'::jsonb),
    'vc_context_notes', coalesce((select jsonb_agg(to_jsonb(t) || jsonb_build_object('slug', p.slug) order by p.slug, t.retrieved_at, t.value)
      from vc_context_notes t join pub p on p.id = t.firm_id where t.data_status = 'real'), '[]'::jsonb)
  );
$$;
revoke all on function public.published_site_bundle() from public, anon, authenticated;
grant execute on function public.published_site_bundle() to service_role;

create table if not exists public.site_fragments (
  key text primary key,
  html text not null,
  updated_at timestamptz not null default now()
);
alter table public.site_fragments enable row level security;
drop policy if exists site_fragments_read on public.site_fragments;
create policy site_fragments_read on public.site_fragments for select to anon, authenticated using (true);
grant select on public.site_fragments to anon, authenticated;
grant all on public.site_fragments to service_role;

create or replace function public.store_site_fragment(p_key text, p_html text)
returns void
language sql
security definer
set search_path = public
as $$
  insert into site_fragments (key, html) values (p_key, p_html)
  on conflict (key) do update set html = excluded.html, updated_at = now();
$$;
revoke all on function public.store_site_fragment(text, text) from public, anon, authenticated;
grant execute on function public.store_site_fragment(text, text) to service_role;

-- What the public static build may read: list rows, stats, updates, fragments. No report bodies.
create or replace function public.public_site_bundle()
returns jsonb
language sql
stable security definer
set search_path = public
as $$
  select jsonb_build_object(
    'firms', coalesce((select jsonb_agg(to_jsonb(f) order by f.list_sort, f.slug) from firms f where f.published and not f.is_test), '[]'::jsonb),
    'site_stats', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from site_stats t), '[]'::jsonb),
    'site_updates', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from site_updates t), '[]'::jsonb),
    'fragments', coalesce((select jsonb_object_agg(key, html) from site_fragments), '{}'::jsonb)
  );
$$;
revoke all on function public.public_site_bundle() from public;
grant execute on function public.public_site_bundle() to anon, authenticated, service_role;
