-- Lab search matches the firm name, the short name, and the website.
-- Legal names and fund entity names stay in firm_aliases for checks 1 and 6.
-- firm_suggest does not match those two types on a lab firm.
-- A commonly used short name is stored as alias_type short_name, source firm_site.
-- Not called here. After review: select * from public.lab_short_name_aliases(true);
-- Rollback: supabase/rollbacks/20261028200000_lab_suggest_names.sql

alter table public.firm_aliases drop constraint if exists firm_aliases_alias_type_chk;
alter table public.firm_aliases add constraint firm_aliases_alias_type_chk
  check (alias_type is null or alias_type in ('display', 'legal', 'fund_entity', 'old_name', 'website', 'short_name'));
comment on column public.firm_aliases.alias_type is
  'display, short name, legal, fund entity, old name, or website. The page does not read this. Lab search uses display, short name, and website.';

create table if not exists public.lab_short_name_log (
  firm_id uuid not null,
  alias text not null,
  action text not null check (action in ('insert', 'retype')),
  old_type text,
  old_source text,
  added_at timestamptz not null default now(),
  unique (firm_id, alias)
);
alter table public.lab_short_name_log enable row level security;
revoke all on public.lab_short_name_log from public, anon, authenticated;
comment on table public.lab_short_name_log is
  'Short-name aliases this step added or retyped. The rollback undoes those rows. Do not drop this table first.';

create or replace function public.lab_short_name_aliases(p_write boolean default false)
returns table(slug text, alias text, action text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare r record; cur_type text; cur_source text;
begin
  create temp table if not exists short_cand (
    firm_id uuid, slug text, alias text, action text, old_type text, old_source text
  ) on commit drop;
  truncate short_cand;

  for r in
    select f.id, f.slug, btrim(f.short_name) as short_name
    from firms f
    where f.deleted_at is null and public._lab_firm(f.id)
      and coalesce(btrim(f.short_name), '') <> ''
  loop
    select a.alias_type, a.source into cur_type, cur_source
    from firm_aliases a
    where a.firm_id = r.id and lower(a.alias) = lower(r.short_name);
    if not found then
      insert into short_cand(firm_id, slug, alias, action) values (r.id, r.slug, r.short_name, 'insert');
    elsif cur_type = 'old_name' or cur_type is null then
      insert into short_cand(firm_id, slug, alias, action, old_type, old_source)
      values (r.id, r.slug, r.short_name, 'retype', cur_type, cur_source);
    end if;
  end loop;

  if p_write then
    insert into firm_aliases(firm_id, alias, source, alias_type)
    select c.firm_id, c.alias, 'firm_site', 'short_name'
    from short_cand c
    where c.action = 'insert';
    update firm_aliases a
    set alias_type = 'short_name', source = 'firm_site'
    from short_cand c
    where c.action = 'retype' and a.firm_id = c.firm_id and lower(a.alias) = lower(c.alias);
    insert into lab_short_name_log(firm_id, alias, action, old_type, old_source)
    select c.firm_id, c.alias, c.action, c.old_type, c.old_source
    from short_cand c
    on conflict (firm_id, alias) do nothing;
  end if;

  return query
  select c.slug, c.alias, c.action from short_cand c order by c.slug, c.alias;
end $$;
revoke all on function public.lab_short_name_aliases(boolean) from public, anon, authenticated;

-- Lab firms: aliases of type display, short_name, or website only.
-- Other firms still match every alias. The suggestion shape is unchanged.
create or replace function public.firm_suggest(q text)
returns json language sql stable security definer set search_path = public as $$
  with t as (select lower(trim(q)) t), pub as (
    select f.* from firms f where f.published and not coalesce(f.is_test, false) and f.data_status = 'real' and f.deleted_at is null
  ), m as (
    select f.slug, coalesce(f.display_name, f.name) as name, f.short_name, f.hq, f.indexable,
      case when lower(coalesce(f.display_name, f.name)) like t || '%' or lower(coalesce(f.short_name, '')) like t || '%' or f.slug like t || '%' then 0
           when lower(coalesce(f.display_name, f.name)) ~ ('\m' || regexp_replace(t, '([^a-z0-9 ])', '\\\1', 'g')) then 1 else 2 end r
    from pub f, t
    where length(t) > 0
      and (lower(coalesce(f.display_name, f.name)) like '%' || t || '%' or lower(coalesce(f.short_name, '')) like '%' || t || '%' or f.slug like '%' || t || '%')
    union all
    select f.slug, coalesce(f.display_name, f.name), f.short_name, f.hq, f.indexable,
      case when lower(a.alias) like t || '%' then 0 when lower(a.alias) ~ ('\m' || regexp_replace(t, '([^a-z0-9 ])', '\\\1', 'g')) then 1 else 2 end
    from firm_aliases a join pub f on f.id = a.firm_id, t
    where length(t) > 0 and lower(a.alias) like '%' || t || '%'
      and (not public._lab_firm(f.id) or a.alias_type in ('display', 'short_name', 'website'))
  ), d as (select slug, name, short_name, hq, indexable, min(r) r from m group by slug, name, short_name, hq, indexable)
  select coalesce(json_agg(json_build_object('slug', slug, 'name', name, 'short_name', short_name, 'hq', hq) order by not indexable, r, name), '[]')
  from (select * from d order by not indexable, r, name limit 8) x
$$;
