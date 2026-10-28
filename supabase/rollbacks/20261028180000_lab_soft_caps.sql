-- Puts archived lab deals back on the hot list. Does not delete lab_cap_archive.
-- Leads hidden by this step are shown again.

update public.investments i
set archived_at = null
from public.lab_cap_archive a
where a.kind = 'deals' and a.firm_id = i.firm_id and a.item_key = i.id::text;

update public.firm_profile_facts
set hidden = false, hidden_reason = null
where section = 'lps' and hidden_reason = 'lead';

drop table if exists public.lab_cap_alerts;

create or replace function public._firm_activity(p_firm uuid, p_open boolean)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  since date := current_date - 365;
  d0 jsonb; r0 jsonb; fund jsonb;
  n_deals int; n_deals12 int; n_revs int; n_close12 int;
begin
  select count(*), count(*) filter (where i.invested_on >= since) into n_deals, n_deals12
    from investments i where i.firm_id = p_firm and i.data_status = 'real';
  select _activity_deal(i, c) into d0
    from investments i left join portfolio_companies c on c.id = i.company_id
   where i.firm_id = p_firm and i.data_status = 'real'
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

alter table public.investments drop column if exists archived_at;
alter table public.press_item_firms drop column if exists archived_at;
alter table public.timeline_events drop column if exists archived_at;

drop function if exists public.lab_soft_caps(boolean);
