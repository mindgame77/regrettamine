-- Rollback for 20261029270000_fix2_money_format.sql (A15.8 money format).
-- Restores _firm_assets, _firm_activity and _entry_check_reasons as they were live before fix 2,
-- then drops the new checks, columns and helpers. No existing data is changed by the forward
-- migration except the *_currency backfill ('USD'), which these drops remove.
CREATE OR REPLACE FUNCTION public._firm_assets(p_firm uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(
    (select (regexp_match(f.value, '\$[0-9][0-9,]*(?:\.[0-9]+)?(?:[[:space:]]*(?:trillion|billion|bn|million|mn|mm|thousand|[TBMK])(?![[:alnum:]]))?', 'i'))[1]
       from firm_profile_facts f
      where f.firm_id = p_firm and not f.hidden
        and f.value ~* '(item[[:space:]]*5[[:space:]]*f|regulatory[[:space:]]+aum|regulatory[[:space:]]+assets)'
        and f.value !~* 'schedule[[:space:]]*d|gross[[:space:]]+asset'
        and f.value ~ '\$[0-9]'
      order by case when f.value ~* 'item[[:space:]]*5[[:space:]]*f' then 0 else 1 end, f.sort_order
      limit 1),
    (select fi.aum_display from firms fi where fi.id = p_firm and fi.aum_display ~ '^\$')
  );
$function$
;

CREATE OR REPLACE FUNCTION public._firm_activity(p_firm uuid, p_open boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  since date := current_date - 365;
  d0 jsonb; r0 jsonb; fund jsonb; sec jsonb; fsec jsonb; n_fsec int;
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
    select x.name, coalesce(x.raised_usd, x.size_usd) amt, x.closed_on,
           coalesce((select u from unnest(array_prepend(nullif(x.filing_url, ''), coalesce(x.source_urls, '{}'))) u
                      where u ~* '^https?://([a-z0-9-]+\.)*sec\.gov/' limit 1), '') url
      from funds x where x.firm_id = p_firm and x.data_status = 'real'
       and btrim(coalesce(x.name, '')) <> ''
       and x.name !~* '^(funds|newest funds|private funds( on file)?|regulatory aum|assets under management|fund gross assets|aum)$')
  select count(*) filter (where url <> ''),
         jsonb_agg(jsonb_build_object('name', name, 'raised_usd', amt, 'date', closed_on, 'url', url) order by closed_on desc nulls last, name)
           filter (where url <> '')
    into n_fsec, fsec from s;
  if fsec is not null then select jsonb_agg(e) into fsec from (select e from jsonb_array_elements(fsec) e limit 100) z; end if;
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
    'funds_sec', jsonb_build_object('n', coalesce(n_fsec, 0), 'items', case when p_open then coalesce(fsec, '[]'::jsonb) end),
    'lazy', true);
end $function$
;

CREATE OR REPLACE FUNCTION public._entry_check_reasons(p jsonb, p_firm_dom text)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  r text[] := '{}';
  it record; recs jsonb; rec jsonb; raw jsonb; lvl int; sec text;
  dom text := nullif(regexp_replace(lower(coalesce(p_firm_dom, '')), '^www\.', ''), '');
begin
  if p is null or jsonb_typeof(p) <> 'object' then return array['empty or unreadable upload']; end if;
  recs := case when jsonb_typeof(p->'records') = 'array' then p->'records' else '[]'::jsonb end;

  if not exists (select 1 from public._checker_payload_items(p)) then
    r := r || 'no items in the upload'::text;
  end if;

  for it in select * from public._checker_payload_items(p) loop
    rec := case when it.n >= 1 and jsonb_typeof(p->'records') = 'array' then recs->(it.n - 1) else null end;
    sec := public._entry_section(it.section, rec->>'field_path');
    -- 1) link present and well-formed http(s)
    if it.url is null or btrim(it.url) = '' then
      r := r || 'no source link'::text;
    elsif btrim(it.url) !~* '^https?://[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+(:\d+)?([/?#][^\s]*)?$' then
      r := r || 'source link is not a valid http(s) URL'::text;
    elsif public._src_search_page(it.url) then
      r := r || 'source link is a search or chat page'::text;
    end if;
    -- 2) source level 1 to 3
    -- Sections shape: the parsed item drops tier/source_level, so read them from the raw item (fix, step B).
    raw := case when rec is null and jsonb_typeof(p->'sections') = 'object'
                then (select c.item from public.checked_items(p) c where c.n = it.n and c.outcome = 'ok' limit 1) end;
    lvl := case when it.n = 0 then 2 else public._entry_level(rec, coalesce(raw, it.f)) end;  -- n = 0: the firm's own website item
    if lvl is null then r := r || 'no source level'::text;
    elsif lvl not between 1 and 3 then r := r || ('source level ' || lvl || ' is not 1 to 3')::text;
    end if;
    -- 4) dates: never rejected; normalized or cleared by _entry_fix_payload.
    -- 5) status words
    if it.section = 'legal' and public._entry_status_bad(it.f) is not null then r := r || public._entry_status_bad(it.f); end if;
    -- 5b) AUM basis press removed (A7.3)
    if rec->>'field_path' = 'aum' and lower(coalesce(rec->'value'->>'basis', '')) = 'press' then
      r := r || 'AUM basis press is not allowed (A7.3)'::text;
    end if;
    -- 6b) thesis over 1,000 characters (A9.19): never rejected; cut by _entry_fix_payload.
    -- 7) no news from the firm's own site
    if sec in ('press', 'news', 'timeline') and dom is not null and it.url is not null
       and (public._dom(it.url) = dom or public._dom(it.url) like '%.' || dom) then
      r := r || 'news item from the firm''s own website or blog'::text;
    end if;
  end loop;

  -- 6) A9 list limits: never rejected; extra items archived by _entry_fix_payload.

  return (select coalesce(array_agg(x order by o), '{}') from (select x, min(o) o from unnest(r) with ordinality u(x, o) group by x) s);
end $function$
;

alter table public.funds drop constraint if exists funds_size_money, drop constraint if exists funds_raised_money,
                         drop constraint if exists funds_target_money;
alter table public.funds drop column if exists size_currency, drop column if exists raised_currency, drop column if exists target_currency;
alter table public.firms drop constraint if exists firms_aum_money, drop constraint if exists firms_fund_assets_money;
alter table public.firms drop column if exists aum_amount, drop column if exists aum_currency,
                         drop column if exists fund_assets_amount, drop column if exists fund_assets_currency;
comment on column public.firms.aum_billions is null;
comment on column public.firms.aum_display is null;
drop function if exists public._money_problems(text, jsonb);
drop function if exists public._money_display(numeric, text);
drop function if exists public._money_iso(text);
