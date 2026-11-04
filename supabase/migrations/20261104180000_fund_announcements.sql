-- Announced funds: a firm's own fund announcement (e.g. a16z "New Funds, New Era", 2024-04-16).
-- Separate from Form D rows in funds (no copies there). Returned by _firm_activity -> firm_page as activity.funds_announced.
create table if not exists public.firm_fund_announcements (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  name text not null check (btrim(name) <> ''),
  amount_usd numeric not null check (amount_usd > 0),
  display text not null,
  announced_on date not null,
  url text not null check (url ~* '^https://'),
  retrieved_on date not null,
  data_status data_status not null default 'real',
  created_at timestamptz not null default now(),
  unique (firm_id, url, name)
);
alter table public.firm_fund_announcements enable row level security;
revoke all on public.firm_fund_announcements from anon, authenticated;

insert into public.firm_fund_announcements (firm_id, name, amount_usd, display, announced_on, url, retrieved_on)
select f.id, v.name, v.amt, v.disp, date '2024-04-16', 'https://a16z.com/new-funds-new-era/', date '2026-11-04'
  from public.firms f, (values
  ('American Dynamism', 600000000, '$600M'),
  ('Apps', 1000000000, '$1B'),
  ('Games', 600000000, '$600M'),
  ('Infrastructure', 1250000000, '$1.25B'),
  ('Growth', 3750000000, '$3.75B')) v(name, amt, disp)
 where f.slug = 'a16z'
on conflict (firm_id, url, name) do nothing;

CREATE OR REPLACE FUNCTION public._firm_activity(p_firm uuid, p_open boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  since date := current_date - 365;
  d0 jsonb; r0 jsonb; fund jsonb; sec jsonb; fsec jsonb; n_fsec int;
  fann jsonb; ann0 jsonb; n_ann int;
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
           -- Fix 2 (A15.8): currency and page display only when an amount is stored (no amount = same output as before).
           || case when coalesce(x.raised_usd, x.size_usd) is null then '{}'::jsonb else jsonb_build_object(
                'currency', case when x.raised_usd is not null then x.raised_currency else x.size_currency end,
                'raised_display', public._money_display(coalesce(x.raised_usd, x.size_usd),
                                  case when x.raised_usd is not null then x.raised_currency else x.size_currency end)) end
           || case when x.target_usd is null then '{}'::jsonb else jsonb_build_object(
                'target_currency', x.target_currency, 'target_display', public._money_display(x.target_usd, x.target_currency)) end
    into fund
    from funds x where x.firm_id = p_firm and x.data_status = 'real'
     -- Fix 1 (B6d.6): only a fund with a real date (closed_on, else vintage) can be the latest fund; a row with
     -- no date and no amount is skipped, and with no dated fund there is no latest fund (the tile hides).
     and (x.closed_on is not null or x.vintage is not null)
     and not public._fund_heading_name(x.name)
   order by coalesce(x.closed_on, make_date(x.vintage, 1, 1)) desc, x.closed_on desc nulls last, x.created_at desc, x.id limit 1;
  -- B6c.1/B6c.8/A1.8: name the fund link's real source. sec.gov is a filing (null label; the page says "Filing").
  -- Else the trusted page label, else the outlet name stored on real press items for that domain; else null (the page shows the host).
  if fund is not null and fund->>'url' is not null then
    fund := fund || jsonb_build_object('url_label', (
      with h as (select lower(regexp_replace(coalesce(substring(fund->>'url' from '^https?://([^/:?#]+)'), ''), '^www\.', '')) host)
      select case when h.host = '' or h.host ~ '(^|\.)sec\.gov$' then null else coalesce(
        (select t.label from trusted_source_domains t
          where t.path_like is null and nullif(trim(t.label), '') is not null
            and (h.host = lower(t.domain) or h.host like '%.' || lower(t.domain))
          order by length(t.domain) desc limit 1),
        (select p.publisher from press_items p
          where p.data_status = 'real' and nullif(trim(p.publisher), '') is not null
            and lower(regexp_replace(coalesce(p.domain, ''), '^www\.', '')) = h.host
          group by p.publisher order by count(*) desc, p.publisher limit 1)) end
      from h));
  end if;
  -- A9.6: funds on SEC record = real fund rows with a sec.gov source, not ADV summary rows ("Funds", "Regulatory AUM", ...).
  -- The count is always sent; the list (newest first, at most 100) only after a credit.
  with s as (
    select x.name, coalesce(x.raised_usd, x.size_usd) amt,
           case when x.raised_usd is not null then x.raised_currency else x.size_currency end cur, x.closed_on,
           coalesce((select u from unnest(array_prepend(nullif(x.filing_url, ''), coalesce(x.source_urls, '{}'))) u
                      where u ~* '^https?://([a-z0-9-]+\.)*sec\.gov/' limit 1), '') url
      from funds x where x.firm_id = p_firm and x.data_status = 'real'
       and btrim(coalesce(x.name, '')) <> ''
       and x.name !~* '^(funds|newest funds|private funds( on file)?|regulatory aum|assets under management|fund gross assets|aum)$')
  select count(*) filter (where url <> ''),
         jsonb_agg(jsonb_build_object('name', name, 'raised_usd', amt, 'date', closed_on, 'url', url)
                   || case when amt is null then '{}'::jsonb else jsonb_build_object('currency', cur, 'raised_display', public._money_display(amt, cur)) end order by closed_on desc nulls last, name)
           filter (where url <> '')
    into n_fsec, fsec from s;
  if fsec is not null then select jsonb_agg(e) into fsec from (select e from jsonb_array_elements(fsec) e limit 100) z; end if;
  -- Announced funds (firm's own announcement, not Form D): count + latest announcement total always; rows only after a credit.
  select count(*), jsonb_agg(jsonb_build_object('name', a.name, 'raised_usd', a.amount_usd, 'raised_display', a.display,
           'date', a.announced_on, 'url', a.url) order by a.announced_on desc, a.amount_usd desc, a.name)
    into n_ann, fann from firm_fund_announcements a where a.firm_id = p_firm and a.data_status = 'real';
  select jsonb_build_object('n', count(*), 'total_usd', sum(a.amount_usd), 'total_display', public._money_display(sum(a.amount_usd), 'USD'),
           'date', max(a.announced_on), 'url', max(a.url))
    into ann0 from firm_fund_announcements a
   where a.firm_id = p_firm and a.data_status = 'real'
     and (a.announced_on, a.url) = (select b.announced_on, b.url from firm_fund_announcements b
                                     where b.firm_id = p_firm and b.data_status = 'real' order by b.announced_on desc, b.url limit 1)
  having count(*) > 0;
  -- Lab firms only, unlocked, more than 10 deals in 12 months: top 10 sectors plus one Other
  -- (the rest and deals with no sector). One grouped read of the firm's own deal rows.
  if p_open and n_deals12 > 10 and public._lab_firm(p_firm) then
    with g as (
      select nullif(btrim(c.sector), '') s, count(*)::int n
        from investments i left join portfolio_companies c on c.id = i.company_id
       where i.firm_id = p_firm and i.data_status = 'real' and i.invested_on >= since
       group by 1),
    r as (select s, n, row_number() over (order by n desc, s) k from g where s is not null)
    select jsonb_build_object('n', n_deals12,
             'top', coalesce((select jsonb_agg(jsonb_build_object('s', s, 'n', n) order by k) from r where k <= 10), '[]'),
             'other', coalesce((select sum(n) from r where k > 10), 0) + coalesce((select n from g where s is null), 0))
      into sec;
  end if;
  return jsonb_build_object(
    'active', n_deals12 > 0 or n_close12 > 0, 'deals_12m', n_deals12, 'funds_closed_12m', n_close12,
    'latest_fund', fund, 'latest_deal', d0, 'latest_review', r0,
    'counts', jsonb_build_object('deals', n_deals, 'reviews', n_revs),
    'deals', case when p_open then case when d0 is null then '[]'::jsonb else jsonb_build_array(d0) end end,
    'reviews', case when p_open then case when r0 is null then '[]'::jsonb else jsonb_build_array(r0) end end,
    'sector_12m', sec,
    'funds_announced', jsonb_build_object('n', coalesce(n_ann, 0), 'latest', ann0, 'items', case when p_open then coalesce(fann, '[]'::jsonb) end),
    'funds_sec', jsonb_build_object('n', coalesce(n_fsec, 0), 'items', case when p_open then coalesce(fsec, '[]'::jsonb) end),
    'lazy', true);
end $function$
;
