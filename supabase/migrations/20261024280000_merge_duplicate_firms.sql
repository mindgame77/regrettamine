-- Duplicate firm pages: merge_firms(keep, drop) folds one page into another (docs/DEDUPE.md).
-- The dropped page is soft-deleted (deleted_at, unpublished), its slug 301s to the kept slug (firm_slug_redirects -> firm_redirect RPC -> edge),
-- its names become aliases (source 'merged') so search still finds it, and its queue entry points at the kept one
-- (research_queue.duplicate_of), so new research for it lands on the kept page. Bot raw data (research_submissions) is never touched.

alter table public.firm_aliases drop constraint if exists firm_aliases_source_check;
alter table public.firm_aliases add constraint firm_aliases_source_check
  check (source in ('sec_legal', 'previous_display', 'queue_name', 'merged'));

create table if not exists public.firm_slug_redirects (
  old_slug text primary key,
  new_slug text not null,
  old_firm_id uuid,
  old_registry_id text,
  reason text,
  merged_at timestamptz not null default now(),
  check (old_slug <> new_slug)
);
alter table public.firm_slug_redirects enable row level security;
revoke all on public.firm_slug_redirects from anon, authenticated;

-- Where an old slug lives now (follows chains, only to a live page). Used by the /vc/ edge for the 301.
create or replace function public.firm_redirect(p_slug text) returns text
language plpgsql stable security definer set search_path = public as $$
declare s text := lower(btrim(coalesce(p_slug, ''))); n text; i int := 0; k text;
begin
  loop
    select new_slug into n from firm_slug_redirects where old_slug = s;
    exit when n is null or i > 5;
    s := n; n := null; i := i + 1;
  end loop;
  if i > 0 and exists (select 1 from firms f where f.slug = s and f.published and f.deleted_at is null and not coalesce(f.is_test, false)) then return s; end if;
  -- No redirect row: a common slug ('sequoia-capital', 'andreessen-horowitz', 'benchmark') is matched by name against the
  -- live firms' name / display name / short name / aliases (same key as search dedupe). Only an unambiguous match redirects.
  if s !~ '^[a-z0-9][a-z0-9-]{1,80}$' then return null; end if;
  k := _queue_name_key(replace(lower(btrim(coalesce(p_slug, ''))), '-', ' '));
  if length(coalesce(k, '')) < 2 then return null; end if;
  select min(f.slug), count(distinct f.id) into n, i from firms f
   where f.deleted_at is null and f.published and not coalesce(f.is_test, false) and f.data_status = 'real'
     and (_queue_name_key(f.name) = k or _queue_name_key(f.display_name) = k or _queue_name_key(f.short_name) = k
          or exists (select 1 from firm_aliases a where a.firm_id = f.id and _queue_name_key(a.alias) = k));
  if i = 1 and n <> lower(btrim(p_slug)) then return n; end if;
  return null;
end $$;
revoke all on function public.firm_redirect(text) from public;
grant execute on function public.firm_redirect(text) to anon, authenticated, service_role;

create or replace function public.merge_firms(p_keep text, p_drop text, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k firms; d firms; moved int := 0;
begin
  select * into k from firms where slug = lower(p_keep) and deleted_at is null;
  select * into d from firms where slug = lower(p_drop) and deleted_at is null;
  if k.id is null or d.id is null then return jsonb_build_object('status', 'skipped', 'keep', p_keep, 'drop', p_drop); end if;
  if k.id = d.id then return jsonb_build_object('status', 'same'); end if;

  -- 301s: the dropped slug and anything that already redirected to it
  update firm_slug_redirects set new_slug = k.slug where new_slug = d.slug;
  insert into firm_slug_redirects (old_slug, new_slug, old_firm_id, old_registry_id, reason)
  values (d.slug, k.slug, d.id, d.registry_id, p_reason)
  on conflict (old_slug) do update set new_slug = excluded.new_slug, reason = excluded.reason, merged_at = now();
  delete from firm_slug_redirects where old_slug = k.slug;

  -- old names stay searchable on the kept page
  insert into firm_aliases (firm_id, alias, source)
  select k.id, a, 'merged' from (select unnest(array[d.name, d.display_name, d.legal_name]) a
                                 union select alias from firm_aliases where firm_id = d.id) x
  where nullif(btrim(a), '') is not null and lower(a) not in (lower(coalesce(k.display_name, k.name)))
  on conflict do nothing;

  -- the queue entry (and its own duplicates) now resolve to the kept page; unresearched entries are no longer claimable
  if k.registry_id is not null and d.registry_id is not null and k.registry_id <> d.registry_id then
    update research_queue set duplicate_of = k.registry_id where duplicate_of = d.registry_id;
    update research_queue q set duplicate_of = k.registry_id,
           status = case when q.status = 'queued' and not exists (select 1 from research_submissions s where s.registry_id = q.registry_id)
                         then 'skipped' else q.status end,
           last_error = coalesce(q.last_error, 'merged into ' || k.registry_id), updated_at = now()
     where q.registry_id = d.registry_id;
  end if;

  -- people who follow the dropped page follow the kept one
  update watchlist w set firm_id = k.id where w.firm_id = d.id
     and not exists (select 1 from watchlist o where o.firm_id = k.id and o.profile_id = w.profile_id);
  get diagnostics moved = row_count;

  update firms set deleted_at = now(), published = false, indexable = false, updated_at = now() where id = d.id;
  return jsonb_build_object('status', 'merged', 'keep', k.slug, 'drop', d.slug, 'watchers_moved', moved);
end $$;
revoke all on function public.merge_firms(text, text, text) from public, anon, authenticated;
grant execute on function public.merge_firms(text, text, text) to service_role;

-- Duplicate candidates for review: same name_key, same CRD or same website among live pages.
create or replace view public.firm_duplicate_candidates as
with f as (
  select f.id, f.slug, coalesce(f.display_name, f.name) name, f.indexable, f.registry_id,
         public._queue_name_key(coalesce(f.display_name, f.name)) k, nullif(f.sec_crd, '') crd,
         nullif(lower(regexp_replace(coalesce(f.primary_domain, ''), '^www\.', '')), '') dom
  from firms f where f.deleted_at is null and f.published and not coalesce(f.is_test, false) and f.data_status = 'real')
select 'name' match_by, k match_key, array_agg(slug order by indexable desc, slug) slugs from f where length(coalesce(k, '')) >= 3 group by k having count(*) > 1
union all select 'crd', crd, array_agg(slug order by indexable desc, slug) from f where crd is not null group by crd having count(*) > 1
union all select 'website', dom, array_agg(slug order by indexable desc, slug) from f where dom is not null group by dom having count(*) > 1;
revoke all on public.firm_duplicate_candidates from public, anon, authenticated;
grant select on public.firm_duplicate_candidates to service_role;
