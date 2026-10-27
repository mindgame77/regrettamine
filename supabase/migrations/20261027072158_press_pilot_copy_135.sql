-- Press step (a) for the 135 pilot firms. Review only until Alex says to apply.
-- Inserts missing press rows. Does not update or delete an existing press row.
-- Does not mark any firm migrated, so readers keep their current path.
-- Rows are tagged source_system / checked_source = 'pilot-copy-135'.
--
-- A URL is copied only when every current vc press note for that firm and URL
-- says the same thing. Two different texts on one URL are left in vc_source_facts
-- (docs/CONFLICT_RULE.md). Nothing there is deleted.
-- data_status is copied as stored. needs_proof stays off the press section,
-- which already shows only real rows.

create table if not exists public.firm_migrated (
  firm_id uuid not null references public.firms(id) on delete cascade,
  kind text not null check (kind in ('press', 'timeline', 'people', 'reviews', 'legal', 'funds', 'deals')),
  migrated_at timestamptz not null default now(),
  primary key (firm_id, kind)
);
alter table public.firm_migrated enable row level security;
revoke all on table public.firm_migrated from anon, authenticated;
comment on table public.firm_migrated is
  'Set when readers for this firm and kind should use the chosen home. This press copy does not insert rows.';

create temp table _press_pilot_pick on commit drop as
with pilot as (
  select f.id
  from public.firms f
  where f.deleted_at is null
    and (
      f.slug = 'a16z'
      or f.registry_id in (
        select s.registry_id
        from bots.research_submissions s
        where s.valid
          and (s.bot_id like 'toxy-researcher%' or s.bot_id like 'toxy-dev%')
      )
    )
),
vc as (
  select
    p.id as firm_id,
    v.id as vc_id,
    btrim(v.source_url) as url,
    lower(regexp_replace(regexp_replace(split_part(split_part(btrim(v.source_url), '#', 1), '?', 1), '^https?://(www\.)?', '', 'i'), '/+$', '')) as nurl,
    btrim(coalesce(nullif(v.value->>'headline', ''), nullif(v.value->>'value', ''), '')) as body,
    coalesce(nullif(v.value->>'date', ''), nullif(v.value->>'published_date', ''), '') as fact_date,
    coalesce(nullif(v.value->>'publisher', ''), nullif(v.source_label, ''), '') as publisher,
    v.retrieved_at,
    v.data_status
  from public.vc_source_facts v
  join pilot p on p.id = v.firm_id
  where v.fact_type = 'press_item'
    and v.status = 'current'
    and v.source_url is not null
    and btrim(v.source_url) <> ''
),
fresh as (
  select v.*
  from vc v
  where v.nurl <> ''
    and v.body <> ''
    and not exists (
      select 1
      from public.press_item_firms pf
      join public.press_items pi on pi.id = pf.press_item_id
      where pf.firm_id = v.firm_id
        and lower(regexp_replace(regexp_replace(split_part(split_part(btrim(pi.url), '#', 1), '?', 1), '^https?://(www\.)?', '', 'i'), '/+$', '')) = v.nurl
    )
),
single as (
  select firm_id, nurl
  from fresh
  group by firm_id, nurl
  having count(distinct lower(body)) = 1
)
select distinct on (f.firm_id, f.nurl)
  f.firm_id, f.vc_id, f.url, f.nurl, f.body, f.fact_date, f.publisher, f.retrieved_at, f.data_status
from fresh f
join single s on s.firm_id = f.firm_id and s.nurl = f.nurl
order by f.firm_id, f.nurl, f.vc_id;

alter table public.press_item_firms disable trigger firm_page_cache_inv;

insert into public.press_items (
  publisher, domain, url, published_on, published_label, headline,
  data_status, retrieved_at, source_system, external_id
)
select
  nullif(p.publisher, ''),
  nullif(regexp_replace(substring(p.url from 'https?://([^/]+)'), '^www\.', '', 'i'), ''),
  p.url,
  case when p.fact_date ~ '^\d{4}-\d{2}-\d{2}$' then p.fact_date::date else null end,
  nullif(p.fact_date, ''),
  left(p.body, 400),
  p.data_status,
  coalesce(p.retrieved_at, now()),
  'pilot-copy-135',
  p.vc_id::text
from _press_pilot_pick p
where not exists (
  select 1
  from public.press_items pi
  where lower(regexp_replace(regexp_replace(split_part(split_part(btrim(pi.url), '#', 1), '?', 1), '^https?://(www\.)?', '', 'i'), '/+$', '')) = p.nurl
);

insert into public.press_item_firms (press_item_id, firm_id, sort_order, checked_source)
select
  pi.id,
  p.firm_id,
  coalesce((select max(pf.sort_order) from public.press_item_firms pf where pf.firm_id = p.firm_id), -1)
    + row_number() over (partition by p.firm_id order by p.url),
  'pilot-copy-135'
from _press_pilot_pick p
join public.press_items pi
  on lower(regexp_replace(regexp_replace(split_part(split_part(btrim(pi.url), '#', 1), '?', 1), '^https?://(www\.)?', '', 'i'), '/+$', '')) = p.nurl
where not exists (
  select 1
  from public.press_item_firms pf
  where pf.firm_id = p.firm_id and pf.press_item_id = pi.id
);

alter table public.press_item_firms enable trigger firm_page_cache_inv;
