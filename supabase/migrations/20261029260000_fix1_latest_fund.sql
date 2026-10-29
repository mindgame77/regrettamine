-- Fix 1 (approved by Alex 2026-10-29, step 2): latest-fund pick and the heading-row bug.
-- (a) lab_held_cleanup no longer names a fund from a heading label ('Funds', 'Regulatory AUM', ...); it uses the value,
--     and a funds row whose name is a heading label is rejected by a check constraint.
-- (b) _firm_activity latest_fund: newest real date (closed_on, then vintage); undated rows are skipped; none if no dated fund.
-- Rollback: supabase/rollbacks/20261029260000_fix1_latest_fund_rollback.sql

create or replace function public._fund_heading_name(p text)
 returns boolean language sql immutable parallel safe set search_path to 'public'
as $$ select coalesce(lower(btrim(p)) ~ '^(funds?|newest funds|private funds( on file)?|regulatory aum|assets under management|fund gross assets|aum)$', false) $$;

alter table public.funds drop constraint if exists funds_name_not_heading;
alter table public.funds add constraint funds_name_not_heading check (not public._fund_heading_name(name));

CREATE OR REPLACE FUNCTION public.lab_held_cleanup(p_write boolean DEFAULT false)
 RETURNS TABLE(slug text, kind text, passed integer, failed integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'bots'
AS $function$
#variable_conflict use_column
declare r record; v_url text; v_out text; v_reason text; v_lvl smallint; v_name text; v_role text; v_key text;
  v_home uuid; v_inserted uuid; v_table text;
begin
  drop table if exists pg_temp.held_work;
  drop table if exists pg_temp.held_result;
  create temp table held_work (
    firm_id uuid, slug text, kind text, item_key text, src_table text, src_id text, detail jsonb
  ) on commit drop;
  create temp table held_result (
    slug text, kind text, outcome text, reason text
  ) on commit drop;

  insert into held_work(firm_id, slug, kind, item_key, src_table, src_id, detail)
  select g.firm_id, f.slug, g.kind, g.item_key,
    case
      when g.kind = 'funds' then 'firm_profile_facts'
      when g.kind = 'people' then 'fund_people'
      when g.item_key like 'held:reg:%' then 'regulatory_records'
      when g.item_key like 'held:matter:%' then 'legal_matter_firms'
      else 'firm_lps'
    end,
    case
      when g.item_key like 'held:reg:%' then substring(g.item_key from 10)
      when g.item_key like 'held:matter:%' then substring(g.item_key from 13)
      else substring(g.item_key from 6)
    end,
    g.detail
  from home_merge_log g
  join firms f on f.id = g.firm_id
  where g.action = 'held' and public._lab_firm(g.firm_id);

  for r in select * from held_work loop
    v_url := null; v_out := null; v_reason := null; v_lvl := null; v_name := null; v_role := null; v_home := null; v_inserted := null; v_table := null;
    if r.src_table = 'firm_profile_facts' then
      select (select s.url from fact_sources fs join sources s on s.id = fs.source_id
               where fs.fact_type = 'firm_profile_facts' and fs.fact_id = x.id and s.url ~* '^https?://'
               order by fs.sort_order limit 1),
             -- Fix 1: a heading label ('Funds', 'Regulatory AUM', ...) is not a fund name: use the value. No made-up 'Fund' fallback.
             left(coalesce(case when public._fund_heading_name(x.label) then null else nullif(btrim(x.label), '') end,
                           nullif(btrim(split_part(x.value, ' · ', 1)), '')), 300)
        into v_url, v_name
      from firm_profile_facts x where x.id = r.src_id::uuid;
    elsif r.src_table = 'fund_people' then
      select left(p.full_name, 120), nullif(btrim(fp.role), '')
        into v_name, v_role
      from fund_people fp join people p on p.id = fp.person_id
      where fp.id = r.src_id::uuid;
      v_url := null;
    elsif r.src_table = 'regulatory_records' then
      select left(x.title, 300), case when x.evidence_key ~* '^https?://' then x.evidence_key end
        into v_name, v_url
      from regulatory_records x where x.id = r.src_id::uuid;
    elsif r.src_table = 'legal_matter_firms' then
      select left(m.title, 300), null
        into v_name, v_url
      from legal_matter_firms mf join legal_matters m on m.id = mf.matter_id
      where mf.firm_id = r.firm_id and (mf.id::text = r.src_id or mf.matter_id::text = r.src_id)
      limit 1;
    else
      select left(lp.lp_name, 200), case when lp.source_url ~* '^https?://' then lp.source_url end
        into v_name, v_url
      from firm_lps lp where lp.id::text = r.src_id;
    end if;

    if r.src_table = 'firm_profile_facts' and not exists (select 1 from firm_profile_facts where id = r.src_id::uuid) then continue; end if;
    if r.src_table = 'fund_people' and not exists (select 1 from fund_people where id = r.src_id::uuid) then continue; end if;
    if r.src_table = 'regulatory_records' and not exists (select 1 from regulatory_records where id = r.src_id::uuid) then continue; end if;
    if r.src_table = 'legal_matter_firms' and not exists (select 1 from legal_matter_firms mf where mf.firm_id = r.firm_id and (mf.id::text = r.src_id or mf.matter_id::text = r.src_id)) then continue; end if;
    if r.src_table = 'firm_lps' and not exists (select 1 from firm_lps where id::text = r.src_id) then continue; end if;

    if r.src_table = 'firm_profile_facts' and (v_name is null or public._fund_heading_name(v_name)) then
      v_out := 'failure'; v_reason := 'no fund name (only a heading label such as Funds or Regulatory AUM)';
    elsif v_url is null then
      v_out := 'failure'; v_reason := 'link is not real (missing, not http, or a search/chat page)';
    else
      select d.outcome, d.reason, d.lvl into v_out, v_reason, v_lvl
      from public._checker_decide(r.firm_id,
        case r.kind when 'funds' then 'funds' when 'people' then 'people' when 'legal' then 'legal' else 'lps' end,
        jsonb_build_object('name', v_name, 'label', v_name, 'title', v_name, 'value', coalesce(r.detail->>'value', v_name)),
        v_url, null, null) d;
    end if;
    v_key := coalesce(public._checker_url_key(v_url), 'id:' || r.src_id);
    if coalesce(public._norm_txt(v_name), '') <> '' then
      v_key := coalesce(public._checker_url_key(v_url), 'name:' || public._norm_txt(v_name));
    end if;

    insert into held_result(slug, kind, outcome, reason) values (r.slug, r.kind, v_out, coalesce(v_reason, v_out));

    if p_write and v_out = 'published' then
      if r.src_table = 'firm_profile_facts' then
        insert into home_held_backup(firm_id, kind, table_name, item_key, row_data, result, reason)
        select r.firm_id, r.kind, 'firm_profile_facts', v_key, jsonb_build_object('row', to_jsonb(x), 'url', v_url), 'passed', v_reason
        from firm_profile_facts x where x.id = r.src_id::uuid;
        select u.id into v_home from funds u
         where u.firm_id = r.firm_id and u.dedupe_key = public._fund_key(v_name) and public._fund_key(v_name) is not null
         limit 1;
        if v_home is null then
          insert into funds(firm_id, name, sort_order, data_status, source_system, source_urls, filing_url, dedupe_key)
          values (r.firm_id, v_name, 900, 'real', 'checker',
                  case when v_url is null then '{}'::text[] else array[v_url] end,
                  case when v_url ~* 'sec.gov|adviserinfo' then v_url end,
                  public._fund_key(v_name))
          returning id into v_inserted;
          update home_held_backup set inserted_table = 'funds', inserted_id = v_inserted
           where id = (select max(id) from home_held_backup where firm_id = r.firm_id and item_key = v_key);
        else
          update funds set source_urls = (
            select array(select distinct u from unnest(coalesce(source_urls, '{}'::text[]) || case when v_url is null then '{}'::text[] else array[v_url] end) u)
          ) where id = v_home;
        end if;
        delete from fact_sources where fact_type = 'firm_profile_facts' and fact_id = r.src_id::uuid;
        delete from firm_profile_facts where id = r.src_id::uuid;
      elsif r.src_table = 'fund_people' then
        insert into home_held_backup(firm_id, kind, table_name, item_key, row_data, result, reason)
        select r.firm_id, r.kind, 'fund_people', v_key, jsonb_build_object('row', to_jsonb(fp), 'url', v_url), 'passed', v_reason
        from fund_people fp where fp.id = r.src_id::uuid;
        insert into firm_people_roles(firm_id, kind, person_name, role, sort_order, checked_on, checked_by, source_level)
        values (r.firm_id, case when coalesce(v_role, '') ~* 'board' then 'board' else 'officer' end,
                left(v_name, 120), left(coalesce(v_role, 'Role not stated'), 300), 900, now(), 'Checker', v_lvl)
        returning id into v_inserted;
        update home_held_backup set inserted_table = 'firm_people_roles', inserted_id = v_inserted
         where id = (select max(id) from home_held_backup where firm_id = r.firm_id and item_key = v_key);
        delete from fund_people where id = r.src_id::uuid;
      elsif r.src_table = 'regulatory_records' then
        insert into home_held_backup(firm_id, kind, table_name, item_key, row_data, result, reason)
        select r.firm_id, r.kind, 'regulatory_records', v_key, jsonb_build_object('row', to_jsonb(x), 'url', v_url), 'passed', v_reason
        from regulatory_records x where x.id = r.src_id::uuid;
        insert into firm_legal_items(firm_id, grp, title, sort_order, checked_on, checked_by, source_level)
        values (r.firm_id, 'regulator', left(v_name, 300), 900, now(), 'Checker', v_lvl)
        returning id into v_inserted;
        update home_held_backup set inserted_table = 'firm_legal_items', inserted_id = v_inserted
         where id = (select max(id) from home_held_backup where firm_id = r.firm_id and item_key = v_key);
        delete from regulatory_records where id = r.src_id::uuid;
      elsif r.src_table = 'legal_matter_firms' then
        insert into home_held_backup(firm_id, kind, table_name, item_key, row_data, result, reason)
        select r.firm_id, r.kind, 'legal_matter_firms', v_key, jsonb_build_object('row', to_jsonb(mf), 'url', v_url), 'passed', v_reason
        from legal_matter_firms mf where mf.firm_id = r.firm_id and (mf.id::text = r.src_id or mf.matter_id::text = r.src_id);
        insert into firm_legal_items(firm_id, grp, title, sort_order, checked_on, checked_by, source_level)
        values (r.firm_id, 'case', left(v_name, 300), 900, now(), 'Checker', v_lvl)
        returning id into v_inserted;
        update home_held_backup set inserted_table = 'firm_legal_items', inserted_id = v_inserted
         where id = (select max(id) from home_held_backup where firm_id = r.firm_id and item_key = v_key);
        delete from legal_matter_firms mf where mf.firm_id = r.firm_id and (mf.id::text = r.src_id or mf.matter_id::text = r.src_id);
      else
        insert into home_held_backup(firm_id, kind, table_name, item_key, row_data, result, reason)
        select r.firm_id, r.kind, 'firm_lps', v_key, jsonb_build_object('row', to_jsonb(lp), 'url', v_url), 'passed', v_reason
        from firm_lps lp where lp.id::text = r.src_id;
        insert into firm_profile_facts(firm_id, section, label, value, sort_order, origin, checked_on, checked_by, source_level)
        values (r.firm_id, 'lps', left(v_name, 200), left(coalesce(r.detail->>'name', v_name), 400), 900, 'checker', now(), 'Checker', v_lvl)
        returning id into v_inserted;
        update home_held_backup set inserted_table = 'firm_profile_facts', inserted_id = v_inserted
         where id = (select max(id) from home_held_backup where firm_id = r.firm_id and item_key = v_key);
        delete from firm_lps where id::text = r.src_id;
      end if;
    elsif p_write then
      if r.src_table = 'firm_profile_facts' then
        insert into home_held_backup(firm_id, kind, table_name, item_key, row_data, result, reason)
        select r.firm_id, r.kind, 'firm_profile_facts', v_key, jsonb_build_object('row', to_jsonb(x), 'url', v_url), 'failed', v_reason from firm_profile_facts x where x.id = r.src_id::uuid;
        delete from fact_sources where fact_type = 'firm_profile_facts' and fact_id = r.src_id::uuid;
        delete from firm_profile_facts where id = r.src_id::uuid;
      elsif r.src_table = 'fund_people' then
        insert into home_held_backup(firm_id, kind, table_name, item_key, row_data, result, reason)
        select r.firm_id, r.kind, 'fund_people', v_key, jsonb_build_object('row', to_jsonb(fp), 'url', v_url), 'failed', v_reason from fund_people fp where fp.id = r.src_id::uuid;
        delete from fund_people where id = r.src_id::uuid;
      elsif r.src_table = 'regulatory_records' then
        insert into home_held_backup(firm_id, kind, table_name, item_key, row_data, result, reason)
        select r.firm_id, r.kind, 'regulatory_records', v_key, jsonb_build_object('row', to_jsonb(x), 'url', v_url), 'failed', v_reason from regulatory_records x where x.id = r.src_id::uuid;
        delete from regulatory_records where id = r.src_id::uuid;
      elsif r.src_table = 'legal_matter_firms' then
        insert into home_held_backup(firm_id, kind, table_name, item_key, row_data, result, reason)
        select r.firm_id, r.kind, 'legal_matter_firms', v_key, jsonb_build_object('row', to_jsonb(mf), 'url', v_url), 'failed', v_reason
        from legal_matter_firms mf where mf.firm_id = r.firm_id and (mf.id::text = r.src_id or mf.matter_id::text = r.src_id);
        delete from legal_matter_firms mf where mf.firm_id = r.firm_id and (mf.id::text = r.src_id or mf.matter_id::text = r.src_id);
      else
        insert into home_held_backup(firm_id, kind, table_name, item_key, row_data, result, reason)
        select r.firm_id, r.kind, 'firm_lps', v_key, jsonb_build_object('row', to_jsonb(lp), 'url', v_url), 'failed', v_reason from firm_lps lp where lp.id::text = r.src_id;
        delete from firm_lps where id::text = r.src_id;
      end if;
      insert into rejected_items(firm_id, kind, item_key, reason)
      values (r.firm_id, r.kind, v_key, coalesce(v_reason, 'failed'))
      on conflict (firm_id, kind, item_key) do nothing;
      if coalesce(public._norm_txt(v_name), '') <> '' and v_key <> 'name:' || public._norm_txt(v_name) then
        insert into rejected_items(firm_id, kind, item_key, reason)
        values (r.firm_id, r.kind, 'name:' || public._norm_txt(v_name), coalesce(v_reason, 'failed'))
        on conflict (firm_id, kind, item_key) do nothing;
      end if;
    end if;
  end loop;

  return query
  select r.slug, r.kind,
         count(*) filter (where r.outcome = 'published')::int,
         count(*) filter (where r.outcome is distinct from 'published')::int
  from held_result r
  group by r.slug, r.kind
  order by r.slug, r.kind;
end $function$;

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
end $function$;
