-- Soft caps for the 10 lab firms. Not called here.
-- News 500, confirmed LPs 100, deals 200. Past the cap the oldest eligible rows are
-- marked archived and copied into lab_cap_archive. They are not deleted.
-- Show all still reads the deal rows. Negative news, lawsuits, and regulator
-- actions are never archived. Legal items and the 10 checks have no cap.
-- One lab_cap_alerts row per firm. Leads stay hidden and are not archived.
-- The git copy is data/lab-cap-archive/index.json. It stays empty until this runs.

alter table public.investments add column if not exists archived_at timestamptz;
alter table public.press_item_firms add column if not exists archived_at timestamptz;
alter table public.timeline_events add column if not exists archived_at timestamptz;

create table if not exists public.lab_cap_archive (
  id bigserial primary key,
  firm_id uuid not null,
  kind text not null check (kind in ('news', 'lps', 'deals')),
  item_key text not null,
  row_data jsonb not null,
  created_at timestamptz not null default now(),
  unique (firm_id, kind, item_key)
);
alter table public.lab_cap_archive enable row level security;
revoke all on public.lab_cap_archive from public, anon, authenticated;

create table if not exists public.lab_cap_alerts (
  firm_id uuid primary key,
  kinds text not null,
  created_at timestamptz not null default now()
);
alter table public.lab_cap_alerts enable row level security;
revoke all on public.lab_cap_alerts from public, anon, authenticated;
comment on table public.lab_cap_alerts is 'One row per lab firm the first time a soft cap is passed.';

create or replace function public.lab_soft_caps(p_write boolean default false)
returns table(slug text, kind text, current_n int, cap_n int, would_archive int, protected_n int)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare r record; k text;
begin
  create temp table if not exists cap_rep (
    slug text, kind text, current_n int, cap_n int, would_archive int, protected_n int, firm_id uuid
  ) on commit drop;
  truncate cap_rep;

  insert into cap_rep(slug, kind, current_n, cap_n, would_archive, protected_n, firm_id)
  with lab as (
    select f.id, f.slug from firms f where f.deleted_at is null and public._lab_firm(f.id)
  ), news as (
    select l.id firm_id, l.slug, 'press:' || pf.press_item_id::text item_key, pf.archived_at,
           coalesce(p.published_on, p.created_at::date) as at,
           (p.sentiment = 'neg') as protected
    from lab l
    join press_item_firms pf on pf.firm_id = l.id and not coalesce(pf.hidden, false)
    join press_items p on p.id = pf.press_item_id and p.data_status = 'real'
    union all
    select l.id, l.slug, 'time:' || t.id::text, t.archived_at, null::date,
           (coalesce(t.kind, '') || ' ' || coalesce(t.body, '')) ~* 'lawsuit|regulator|sanction|indict|charged|criminal probe'
    from lab l
    join timeline_events t on t.firm_id = l.id and not coalesce(t.hidden, false)
  ), ranked as (
    select n.*, row_number() over (partition by n.firm_id order by n.at desc nulls last, n.item_key desc) rn,
           count(*) over (partition by n.firm_id) total
    from news n where n.archived_at is null
  )
  select slug, 'news', total::int, 500,
         count(*) filter (where rn > 500 and not protected)::int,
         count(*) filter (where protected)::int,
         firm_id
  from ranked group by slug, firm_id, total;

  insert into cap_rep(slug, kind, current_n, cap_n, would_archive, protected_n, firm_id)
  with lab as (
    select f.id, f.slug from firms f where f.deleted_at is null and public._lab_firm(f.id)
  ), lp as (
    select l.id firm_id, l.slug, p.label,
           (p.value ~* 'not confirmed') as is_lead
    from lab l
    join firm_profile_facts p on p.firm_id = l.id and p.section = 'lps' and not coalesce(p.hidden, false)
  )
  select slug, 'lps', count(distinct label) filter (where not is_lead)::int, 100, 0,
         count(*) filter (where is_lead)::int, firm_id
  from lp group by slug, firm_id;

  insert into cap_rep(slug, kind, current_n, cap_n, would_archive, protected_n, firm_id)
  with lab as (
    select f.id, f.slug from firms f where f.deleted_at is null and public._lab_firm(f.id)
  ), d as (
    select l.id firm_id, l.slug, i.id, i.archived_at,
           row_number() over (partition by l.id order by i.invested_on desc nulls last, i.id desc) rn,
           count(*) over (partition by l.id) total
    from lab l
    join investments i on i.firm_id = l.id and i.data_status = 'real' and i.archived_at is null
  )
  select slug, 'deals', total::int, 200, count(*) filter (where rn > 200)::int, 0, firm_id
  from d group by slug, firm_id, total;

  if p_write then
    insert into lab_cap_archive(firm_id, kind, item_key, row_data)
    select i.firm_id, 'deals', i.id::text, to_jsonb(i)
    from investments i
    join (
      select id from (
        select i2.id, row_number() over (partition by i2.firm_id order by i2.invested_on desc nulls last, i2.id desc) rn
        from investments i2
        join firms f on f.id = i2.firm_id
        where public._lab_firm(f.id) and i2.data_status = 'real' and i2.archived_at is null
      ) z where rn > 200
    ) x on x.id = i.id
    on conflict (firm_id, kind, item_key) do nothing;
    update investments i set archived_at = now()
    from lab_cap_archive a
    where a.kind = 'deals' and a.item_key = i.id::text and i.archived_at is null and public._lab_firm(i.firm_id);

    update firm_profile_facts p set hidden = true, hidden_reason = 'lead'
    where p.section = 'lps' and not coalesce(p.hidden, false) and p.value ~* 'not confirmed'
      and public._lab_firm(p.firm_id);

    insert into lab_cap_alerts(firm_id, kinds)
    select firm_id, string_agg(kind, ', ' order by kind)
    from cap_rep where would_archive > 0 group by firm_id
    on conflict (firm_id) do nothing;
  end if;

  return query
  select c.slug, c.kind, c.current_n, c.cap_n, c.would_archive, c.protected_n
  from cap_rep c
  order by c.slug, c.kind;
end $$;
revoke all on function public.lab_soft_caps(boolean) from public, anon, authenticated;

-- Hot deal count skips archived rows. Show all still reads every real deal, including archived ones.
create or replace function public._firm_activity(p_firm uuid, p_open boolean)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  since date := current_date - 365;
  d0 jsonb; r0 jsonb; fund jsonb;
  n_deals int; n_deals12 int; n_revs int; n_close12 int;
begin
  select count(*), count(*) filter (where i.invested_on >= since) into n_deals, n_deals12
    from investments i where i.firm_id = p_firm and i.data_status = 'real' and i.archived_at is null;
  select _activity_deal(i, c) into d0
    from investments i left join portfolio_companies c on c.id = i.company_id
   where i.firm_id = p_firm and i.data_status = 'real' and i.archived_at is null
   order by i.invested_on desc nulls last, c.name limit 1;
  select count(*) into n_revs from reviews r
   where r.firm_id = p_firm and r.is_public and r.moderation_status = 'approved';
  select _activity_review(r, c) into r0
    from reviews r left join portfolio_companies c on c.id = r.company_id
   where r.firm_id = p_firm and r.is_public and r.moderation_status = 'approved'
   order by (r.review_type = 'founder') desc, r.reviewed_on desc nulls last, r.created_at desc limit 1;
  select count(*) into n_close12 from funds
   where firm_id = p_firm and data_status = 'real' and closed_on >= since;
  select jsonb_build_object('name', x.name, 'raised_usd', coalesce(x.raised_usd, x.size_usd), 'target_usd', x.target_usd,
           'status', x.close_status, 'date', x.closed_on, 'date_precision', x.date_precision, 'vintage', x.vintage,
           'url', coalesce(nullif(x.filing_url, ''), (select u from unnest(coalesce(x.source_urls, '{}')) u where u ~* '^https?://' limit 1)))
    into fund
    from funds x where x.firm_id = p_firm and x.data_status = 'real'
   order by x.closed_on desc nulls last, x.vintage desc nulls last, x.created_at desc limit 1;
  return jsonb_build_object(
    'active', n_deals12 > 0 or n_close12 > 0, 'deals_12m', n_deals12, 'funds_closed_12m', n_close12,
    'latest_fund', fund, 'latest_deal', d0, 'latest_review', r0,
    'counts', jsonb_build_object('deals', n_deals, 'reviews', n_revs),
    'deals', case when p_open then case when d0 is null then '[]'::jsonb else jsonb_build_array(d0) end end,
    'reviews', case when p_open then case when r0 is null then '[]'::jsonb else jsonb_build_array(r0) end end,
    'lazy', true);
end $$;
revoke all on function public._firm_activity(uuid, boolean) from public, anon, authenticated;
