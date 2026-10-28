-- Lab search names. Not called here.
-- Legal names, fund entity names, and the firm website become aliases so
-- firm_suggest can find them. No second search table.
-- A value is copied only when it comes from a register (sec.gov) or the firm's
-- own domain. A news page is not copied. Section labels such as "Funds" are not
-- fund names. Existing aliases are left as they are.
-- Checks 1 and 6 each read lab_check_search_names for that check. They do not
-- share one search. The website is not one of those check queries.
-- Rollback: supabase/rollbacks/20261028190000_lab_search_aliases.sql

alter table public.firm_aliases drop constraint if exists firm_aliases_source_check;
alter table public.firm_aliases add constraint firm_aliases_source_check
  check (source in ('sec_legal', 'previous_display', 'queue_name', 'merged', 'firm_site'));

alter table public.firm_aliases drop constraint if exists firm_aliases_alias_type_chk;
alter table public.firm_aliases add constraint firm_aliases_alias_type_chk
  check (alias_type is null or alias_type in ('display', 'legal', 'fund_entity', 'old_name', 'website'));
comment on column public.firm_aliases.alias_type is
  'display, legal, fund entity, old name, or website. The source column stays. The page does not read this.';

create table if not exists public.lab_search_alias_log (
  firm_id uuid not null,
  alias text not null,
  alias_type text not null,
  source text not null,
  added_at timestamptz not null default now(),
  unique (firm_id, alias)
);
alter table public.lab_search_alias_log enable row level security;
revoke all on public.lab_search_alias_log from public, anon, authenticated;
comment on table public.lab_search_alias_log is
  'Aliases this step added. The rollback removes those aliases. Do not drop this table first.';

create or replace function public.lab_search_aliases(p_write boolean default false)
returns table(slug text, alias_type text, added int)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
begin
  create temp table if not exists alias_cand (
    firm_id uuid, slug text, alias text, source text, alias_type text, is_new boolean
  ) on commit drop;
  truncate alias_cand;

  insert into alias_cand(firm_id, slug, alias, source, alias_type)
  select f.id, f.slug, btrim(f.legal_name), 'sec_legal', 'legal'
  from firms f
  where f.deleted_at is null and public._lab_firm(f.id)
    and coalesce(f.sec_crd, '') <> '' and coalesce(btrim(f.legal_name), '') <> '';

  insert into alias_cand(firm_id, slug, alias, source, alias_type)
  select f.id, f.slug, lower(btrim(f.primary_domain)), 'firm_site', 'website'
  from firms f
  where f.deleted_at is null and public._lab_firm(f.id)
    and lower(btrim(coalesce(f.primary_domain, ''))) ~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$';

  insert into alias_cand(firm_id, slug, alias, source, alias_type)
  select distinct on (u.firm_id, lower(btrim(u.name)))
    u.firm_id, f.slug, btrim(u.name),
    case when exists (
      select 1 from unnest(coalesce(u.source_urls, '{}') || coalesce(array[u.filing_url], '{}')) s
      where lower(substring(s from '://(?:www\.)?([^/:?#]+)')) ~ '(^|\.)sec\.gov$'
    ) then 'sec_legal' else 'firm_site' end,
    'fund_entity'
  from funds u
  join firms f on f.id = u.firm_id
  where f.deleted_at is null and public._lab_firm(f.id) and u.data_status = 'real'
    and length(btrim(u.name)) between 4 and 160
    and position(':' in u.name) = 0
    and lower(btrim(u.name)) not in (
      'funds', 'newest funds', 'private funds on file', 'regulatory aum', 'assets under management')
    and (
      exists (
        select 1 from unnest(coalesce(u.source_urls, '{}') || coalesce(array[u.filing_url], '{}')) s
        where lower(substring(s from '://(?:www\.)?([^/:?#]+)')) ~ '(^|\.)sec\.gov$'
      )
      or exists (
        select 1 from unnest(coalesce(u.source_urls, '{}') || coalesce(array[u.filing_url], '{}')) s
        where coalesce(f.primary_domain, '') <> ''
          and lower(substring(s from '://(?:www\.)?([^/:?#]+)')) = lower(f.primary_domain)
      )
    )
  order by u.firm_id, lower(btrim(u.name)),
    case when exists (
      select 1 from unnest(coalesce(u.source_urls, '{}') || coalesce(array[u.filing_url], '{}')) s
      where lower(substring(s from '://(?:www\.)?([^/:?#]+)')) ~ '(^|\.)sec\.gov$'
    ) then 0 else 1 end;

  update alias_cand c set is_new = not exists (
    select 1 from firm_aliases a
    where a.firm_id = c.firm_id and lower(a.alias) = lower(c.alias)
  );

  if p_write then
    insert into firm_aliases(firm_id, alias, source, alias_type)
    select c.firm_id, c.alias, c.source, c.alias_type
    from alias_cand c
    where c.is_new;
    insert into lab_search_alias_log(firm_id, alias, alias_type, source)
    select c.firm_id, c.alias, c.alias_type, c.source
    from alias_cand c
    where c.is_new
    on conflict (firm_id, alias) do nothing;
  end if;

  return query
  select c.slug, c.alias_type, count(*) filter (where c.is_new)::int
  from alias_cand c
  group by c.slug, c.alias_type
  order by c.slug, c.alias_type;
end $$;
revoke all on function public.lab_search_aliases(boolean) from public, anon, authenticated;

-- Names for one check. Pass 1 or 6. The other check is a separate call.
-- Legal names and fund entity names only. The website is not a check query.
create or replace function public.lab_check_search_names(p_firm uuid, p_n int)
returns table(n int, alias text, alias_type text, source text)
language sql stable security definer set search_path = public as $$
  select p_n, a.alias, a.alias_type, a.source
  from firm_aliases a
  where a.firm_id = p_firm
    and public._lab_firm(p_firm)
    and p_n in (1, 6)
    and a.alias_type in ('legal', 'fund_entity')
  order by a.alias_type, a.alias
$$;
revoke all on function public.lab_check_search_names(uuid, int) from public, anon, authenticated;
