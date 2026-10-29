-- Fix 4b: source level and source date for AUM and Fund assets, and a conflict rule that replaces "only if empty".
-- Level 1 is a SEC Form ADV link. Level 2 is the firm's own website (the link host matches the firm's website domain).
-- Level 3 is a SEC DEF 14A filing, a press release or news on another site, or another trusted page.
-- AUM accepts level 1, else level 2, else level 3 only when the firm has no level 1 or level 2 AUM.
-- Level 1 or 2 always replaces a level 3 AUM. Fund assets accept level 1 only (B6d.6: the SEC filing).
-- When a value is already stored, a higher level (a smaller number: 1 beats 2 beats 3) replaces the amount and the link.
-- A lower level is refused and logged 'blocked' with a reason. The same level replaces only when its source date
-- is newer; otherwise it is blocked.
-- No rows are updated, inserted, or backfilled by this migration. firm_page, the Checker writers, research-ingest,
-- firm_list_row, and aum_billions are not changed. The source level and source date are stored and not drawn.
-- Rollback: supabase/rollbacks/20261029310000_fix4b_source_levels_rollback.sql

alter table public.firms
  add column if not exists aum_source_level smallint,
  add column if not exists aum_source_date date,
  add column if not exists fund_assets_source_level smallint,
  add column if not exists fund_assets_source_date date;

alter table public.firms drop constraint if exists firms_aum_source_adv;
alter table public.firms
  add constraint firms_aum_source_ok check (
    aum_source_url is null
    or public._adv_source_ok(aum_source_url)
    or (
      aum_source_url ~* '^https://'
      and (
        aum_source_url ~* 'def[ _-]?14a'
        or aum_source_url ~* 'press[ _-]?release'
        or (
          public._dom(aum_source_url) !~ '(^|\.)sec\.gov$'
          and public._dom(aum_source_url) !~ '(^|\.)adviserinfo\.sec\.gov$'
        )
      )
    )),
  add constraint firms_aum_source_level_chk check (aum_source_level is null or aum_source_level in (1, 2, 3)),
  add constraint firms_fund_assets_source_level_chk check (fund_assets_source_level is null or fund_assets_source_level = 1);

comment on column public.firms.aum_source_url is 'Link for aum_amount. Level 1 is a Form ADV page. Level 2 is the firm''s own website. Level 3 is a DEF 14A, a press release, or news on another site, and only when no level 1 or 2 is stored.';
comment on column public.firms.aum_source_level is '1 Form ADV, 2 the firm''s own website, 3 DEF 14A or a press release or news on another site. Not shown on the page.';
comment on column public.firms.aum_source_date is 'Date of the AUM source. A same-level value replaces the stored one only when this date is newer. Not shown on the page.';
comment on column public.firms.fund_assets_source_url is 'Form ADV link for fund_assets_amount. The Fund assets tile needs it.';
comment on column public.firms.fund_assets_source_level is '1 Form ADV. Fund assets accept level 1 only. Not shown on the page.';
comment on column public.firms.fund_assets_source_date is 'Date of the Fund assets source. A same-level value replaces the stored one only when this date is newer. Not shown on the page.';

-- The firm's website hosts: the site the page already shows, the primary domain, and a website alias.
create or replace function public._firm_host_match(p_firm uuid, p_url text)
returns boolean
language sql stable security definer set search_path to 'public' as $fn$
  select exists (
    select 1 from (
      select public._dom(public._firm_website(f.id, f.primary_domain)) as h
        from firms f where f.id = p_firm
      union
      select public._dom(case when btrim(f.primary_domain) ~* '^https?://' then btrim(f.primary_domain) else 'https://' || btrim(f.primary_domain) end)
        from firms f where f.id = p_firm and nullif(btrim(f.primary_domain), '') is not null
      union
      select lower(regexp_replace(btrim(a.alias), '^www\.', ''))
        from firm_aliases a
       where a.firm_id = p_firm and a.alias_type = 'website' and nullif(btrim(a.alias), '') is not null
    ) d
    where d.h is not null and d.h <> ''
      and (public._dom(p_url) = d.h or public._dom(p_url) like '%.' || d.h)
  )
$fn$;

-- A date from a source: YYYY-MM-DD, YYYY-MM, YYYY, or an ISO timestamp. Unreadable dates are empty.
create or replace function public._money_source_date(p text)
returns date
language plpgsql stable set search_path to 'public' as $fn$
declare s text := nullif(btrim(p), ''); y int; m int; d int;
begin
  if s is null then return null; end if;
  if s ~ '^\d{4}-\d{2}-\d{2}' then
    y := substring(s from 1 for 4)::int; m := substring(s from 6 for 2)::int; d := substring(s from 9 for 2)::int;
    if m between 1 and 12 and d between 1 and 31 then return make_date(y, m, d); end if;
    return null;
  end if;
  if s ~ '^\d{4}-\d{2}$' then
    y := substring(s from 1 for 4)::int; m := substring(s from 6 for 2)::int;
    if m between 1 and 12 then return make_date(y, m, 1); end if;
    return null;
  end if;
  if s ~ '^\d{4}$' then return make_date(s::int, 1, 1); end if;
  return null;
exception when others then return null;
end $fn$;

-- 1 Form ADV, 2 the firm's own website, 3 a DEF 14A, a press release or news on another site, or another
-- trusted page. A press release on the firm's own site is level 2. A leftover sec.gov page is not a source.
create or replace function public._money_source_level(p_firm uuid, p_url text)
returns smallint
language plpgsql stable security definer set search_path to 'public' as $fn$
declare h text;
begin
  if p_url is null or p_url !~* '^https://' or public.source_tier(p_url) is null then return null; end if;
  if public._adv_source_ok(p_url) then return 1; end if;
  if public._firm_host_match(p_firm, p_url) then return 2; end if;
  if p_url ~* 'def[ _-]?14a' or p_url ~* 'press[ _-]?release' then return 3; end if;
  h := public._dom(p_url);
  if h ~ '(^|\.)(sec\.gov|adviserinfo\.sec\.gov)$' then return null; end if;
  if h ~ '(^|\.)(techcrunch\.com|reuters\.com|bloomberg\.com|axios\.com|ft\.com|wsj\.com|cnbc\.com|forbes\.com|theinformation\.com)$'
     or exists (select 1 from trusted_source_domains t where h = t.domain or h like '%.' || t.domain)
  then return 3; end if;
  return null;
end $fn$;

-- Null when this link may be stored for the field. Otherwise the refusal, in plain words.
create or replace function public._money_source_reason(p_firm uuid, p_kind text, p_url text)
returns text
language plpgsql stable security definer set search_path to 'public' as $fn$
declare lvl smallint;
begin
  lvl := public._money_source_level(p_firm, p_url);
  if lvl is null then return 'no acceptable source link'; end if;
  -- AUM may use level 3. Fund assets stay level 1. The place step blocks a level 3 AUM when level 1 or 2 is stored.
  if p_kind = 'fund_assets' and lvl <> 1 then
    if lvl = 3 then return 'source level 3 is for fund amounts, or for AUM only when no level 1 or 2 is stored'; end if;
    return 'Fund assets accepts source level 1 only';
  end if;
  if p_kind = 'aum' and lvl not in (1, 2, 3) then return 'AUM accepts source level 1, else 2, else 3'; end if;
  return null;
end $fn$;

-- Best link on one record: the higher level, then the newer source date. Reason is set when none is acceptable.
create or replace function public._money_pick_source(p_firm uuid, p_kind text, p_sources jsonb, p_as_of text)
returns table(url text, source_level smallint, source_date date, reason text)
language plpgsql stable security definer set search_path to 'public' as $fn$
declare i int; nsrc int; src jsonb; u text; lvl smallint; dt date; best_u text; best_l smallint; best_d date;
  saw_def boolean := false; saw_press boolean := false; saw_l3 boolean := false; saw_low boolean := false;
begin
  nsrc := coalesce(jsonb_array_length(p_sources), 0);
  for i in 0 .. nsrc - 1 loop
    src := p_sources->i;
    u := src->>'url';
    lvl := public._money_source_level(p_firm, u);
    dt := coalesce(public._money_source_date(src->>'published_at'), public._money_source_date(src->>'as_of'),
                   public._money_source_date(p_as_of), public._money_source_date(src->>'retrieved_at'));
    if (p_kind = 'aum' and lvl in (1, 2, 3)) or (p_kind = 'fund_assets' and lvl = 1) then
      if best_u is null or lvl < best_l or (lvl = best_l and dt is not null and (best_d is null or dt > best_d)) then
        best_u := u; best_l := lvl; best_d := dt;
      end if;
    elsif coalesce(u, '') ~* 'def[ _-]?14a' then saw_def := true;
    elsif coalesce(u, '') ~* 'press[ _-]?release' then saw_press := true;
    elsif lvl = 3 then saw_l3 := true;
    elsif lvl = 2 then saw_low := true;
    end if;
  end loop;
  if best_u is not null then
    url := best_u; source_level := best_l; source_date := best_d; reason := null; return next; return;
  end if;
  url := null; source_level := null; source_date := null;
  reason := case
    when saw_def then 'DEF 14A is not a Form ADV source'
    when saw_press then 'a non-firm press release is not a source for this field'
    when saw_l3 then 'source level 3 is for fund amounts, or for AUM only when no level 1 or 2 is stored'
    when saw_low then 'Fund assets accepts source level 1 only'
    else 'no acceptable source link' end;
  return next;
end $fn$;

-- Write one money field, or return the block reason and write nothing.
-- A higher level replaces the amount, the currency, the link, the level, and the date.
-- The same level replaces only when p_date is strictly newer than the stored source date.
create or replace function public._place_money_source(p_firm uuid, p_kind text, p_amount numeric, p_currency text, p_url text, p_date date)
returns text
language plpgsql security definer set search_path to 'public' as $fn$
declare why text; lvl smallint; cur_amt numeric; cur_lvl smallint; cur_dt date; done int; col text;
begin
  if p_kind not in ('aum', 'fund_assets') then return 'unknown money field'; end if;
  if p_amount is null or p_amount < 1000 or p_amount <> trunc(p_amount) or not public._money_iso(p_currency) then
    return 'no full number plus currency code, so nothing was stored';
  end if;
  why := public._money_source_reason(p_firm, p_kind, p_url);
  if why is not null then return why; end if;
  lvl := public._money_source_level(p_firm, p_url);
  if p_kind = 'aum' then
    select aum_amount, aum_source_level, aum_source_date into cur_amt, cur_lvl, cur_dt from firms where id = p_firm for update;
  else
    select fund_assets_amount, fund_assets_source_level, fund_assets_source_date into cur_amt, cur_lvl, cur_dt from firms where id = p_firm for update;
  end if;
  if not found then return 'firm not found'; end if;
  col := case when p_kind = 'aum' then 'AUM' else 'Fund assets' end;
  if cur_amt is not null then
    cur_lvl := coalesce(cur_lvl, 99); -- a stored amount with no level loses to a ranked source; none are live
    if lvl > cur_lvl then
      return 'source level ' || lvl || ' is lower than the stored level ' || cur_lvl || '; kept the existing value';
    end if;
    if lvl = cur_lvl and not (p_date is not null and cur_dt is not null and p_date > cur_dt) then
      return 'same source level ' || lvl || ', source date ' || coalesce(p_date::text, 'none')
        || ' is not newer than ' || coalesce(cur_dt::text, 'none') || '; kept the existing value';
    end if;
  end if;
  if p_kind = 'aum' then
    update firms set aum_amount = p_amount, aum_currency = p_currency, aum_source_url = p_url,
      aum_source_level = lvl, aum_source_date = p_date where id = p_firm;
  else
    update firms set fund_assets_amount = p_amount, fund_assets_currency = p_currency, fund_assets_source_url = p_url,
      fund_assets_source_level = lvl, fund_assets_source_date = p_date where id = p_firm;
  end if;
  get diagnostics done = row_count;
  if done = 0 then return col || ' was not stored'; end if;
  delete from firm_page_cache where firm_id = p_firm;
  return null;
end $fn$;

-- The two money tiles. Level and date are not included: they are not drawn (A6.4).
-- An ADV link with no stored level still shows, so a row written before this fix keeps its tile.
create or replace function public._firm_money_tiles(p_firm uuid)
returns jsonb language sql stable security definer set search_path to 'public' as $fn$
  select case when public._lab_firm(f.id) then nullif(jsonb_strip_nulls(jsonb_build_object(
    'aum', case when f.aum_amount is not null and (
             (public._adv_source_ok(f.aum_source_url) and coalesce(f.aum_source_level, 1) = 1)
             or (f.aum_source_level = 2 and public._firm_host_match(f.id, f.aum_source_url))
             or (f.aum_source_level = 3 and public._money_source_level(f.id, f.aum_source_url) = 3)
           ) then jsonb_build_object(
             'amount', f.aum_amount, 'currency', f.aum_currency, 'display', public._money_display(f.aum_amount, f.aum_currency),
             'url', f.aum_source_url) end,
    'fund_assets', case when f.fund_assets_amount is not null and public._adv_source_ok(f.fund_assets_source_url)
           and coalesce(f.fund_assets_source_level, 1) = 1 then jsonb_build_object(
             'amount', f.fund_assets_amount, 'currency', f.fund_assets_currency,
             'display', public._money_display(f.fund_assets_amount, f.fund_assets_currency), 'url', f.fund_assets_source_url) end
  )), '{}'::jsonb) end
    from firms f where f.id = p_firm
$fn$;

CREATE OR REPLACE FUNCTION public._money_home_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fn$
declare lbl text; val text; k text; a numeric; c text; fid uuid; routed text; why text; src text; src_date date;
begin
  fid := new.firm_id;
  if tg_table_name = 'firm_profile_facts' then
    lbl := case when public._money_home_label(new.label) then new.label when public._money_home_label(new.hero_label) then new.hero_label end;
    if tg_op = 'UPDATE' and (public._money_home_label(old.label) or public._money_home_label(old.hero_label)) then return new; end if;
    val := concat_ws(' · ', new.hero_value, new.value);
  elsif tg_table_name = 'vc_source_facts' then
    lbl := case when public._money_home_label(new.fact_type) then new.fact_type
                when public._money_home_label(new.value->>'field') then new.value->>'field'
                when public._money_home_label(new.value->>'label') then new.value->>'label' end;
    if tg_op = 'UPDATE' and (public._money_home_label(old.fact_type) or public._money_home_label(old.value->>'field') or public._money_home_label(old.value->>'label')) then return new; end if;
    val := coalesce(new.value->>'value', new.value::text);
  elsif tg_table_name = 'list_items' then
    lbl := case when public._money_home_label(new.group_key) then new.group_key when public._money_home_label(new.name) then new.name end;
    if tg_op = 'UPDATE' and (public._money_home_label(old.group_key) or public._money_home_label(old.name)) then return new; end if;
    val := concat_ws(' · ', new.value, new.note);
  else
    lbl := case when public._money_home_label(new.kind) then new.kind
                when public._money_home_label(substring(new.body from '^\s*([^:·—]{2,40}?)\s*[:·—]')) then substring(new.body from '^\s*([^:·—]{2,40}?)\s*[:·—]') end;
    if tg_op = 'UPDATE' and (public._money_home_label(old.kind) or public._money_home_label(substring(old.body from '^\s*([^:·—]{2,40}?)\s*[:·—]'))) then return new; end if;
    val := new.body;
  end if;
  if lbl is null then return new; end if;
  k := public._money_home_kind(lbl);
  select amount, currency into a, c from public._money_home_full(val);
  if a is null or fid is null or (k = 'fund_assets' and lower(lbl) !~ '^(total |private fund )?(fund assets|gross assets|gav|private fund gav)') then
    why := 'no full number plus currency code for the firm total, so nothing was routed';
  else
    if tg_table_name = 'vc_source_facts' then
      src := new.source_url; src_date := new.retrieved_at::date;
    elsif tg_table_name = 'timeline_events' then
      src := new.source_url; src_date := public._money_source_date(new.date_label);
    else
      src := null; src_date := null;
    end if;
    why := public._place_money_source(fid, k, a, c, src, src_date);
    if why is null then
      routed := 'firms.' || k || '_amount';
      why := 'routed to firms.' || k || '_amount/' || k || '_currency';
    end if;
  end if;
  if routed is not null then delete from public.firm_page_cache where firm_id = fid; end if;
  insert into public.money_home_blocked(table_name, op, firm_id, label, value, routed_to, reason, row_id)
  values (tg_table_name, tg_op, fid, left(lbl, 200), left(val, 500), routed,
          'One home per field (fix 3): ' || case when k = 'aum' then 'AUM' else 'Fund assets' end
          || ' is stored only in firms.' || k || '_amount/' || k || '_currency, not as a ' || tg_table_name || ' row labelled "' || left(lbl, 60) || '". Row not stored; ' || why || '.', new.id);
  return null;
end $fn$;

CREATE OR REPLACE FUNCTION public._route_aum_record(p_firm uuid, qid text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'bots', 'public'
AS $fn$
declare rec record; v jsonb; a numeric; c text; fa numeric; n int := 0; pick record; why text; outc text; amt numeric; ccy text; fld text;
begin
  if qid is null then return 0; end if;
  select s.id sub, r.value r into rec from research_submissions s, jsonb_array_elements(coalesce(s.payload->'records', '[]')) r
   where s.registry_id = qid and s.valid and r->>'field_path' = 'aum'
     and exists (select 1 from jsonb_array_elements(public._rec_sources(s.id, r)) x where coalesce(x->>'url', '') like 'http%' and public._promo_src_ok(x->>'url'))
   order by s.received_at desc, s.id desc limit 1;
  if rec.sub is null then return 0; end if;
  v := rec.r->'value';
  if jsonb_typeof(v) <> 'object' then return 0; end if;
  if lower(coalesce(v->>'basis', '')) = 'press' then return 0; end if;  -- A7.3
  if jsonb_typeof(v->'amount_usd') = 'number' then a := (v->>'amount_usd')::numeric; c := 'USD';
  elsif jsonb_typeof(v->'amount') = 'number' and public._money_iso(upper(v->>'currency')) then a := (v->>'amount')::numeric; c := upper(v->>'currency');
  elsif jsonb_typeof(v->'raum_usd') = 'number' then a := (v->>'raum_usd')::numeric; c := 'USD';
  end if;
  if jsonb_typeof(v->'private_fund_gav_usd') = 'number' then fa := (v->>'private_fund_gav_usd')::numeric; end if;
  if a is not null and (a < 1000 or a <> trunc(a)) then a := null; end if;
  if fa is not null and (fa < 1000 or fa <> trunc(fa)) then fa := null; end if;
  if a is not null then
    fld := 'aum'; amt := a; ccy := c;
    select * into pick from public._money_pick_source(p_firm, fld, public._rec_sources(rec.sub, rec.r), coalesce(rec.r->>'as_of', v->>'as_of'));
    if pick.reason is null then why := public._place_money_source(p_firm, fld, amt, ccy, pick.url, pick.source_date);
    else why := pick.reason; end if;
    outc := case when why is null then 'published' else 'blocked' end;
    if why is null then n := n + 1;
    else insert into public.money_home_blocked(table_name, op, firm_id, label, value, routed_to, reason)
      values ('research_submissions', 'route', p_firm, 'AUM', left(amt::text || ' ' || ccy, 500), null, why); end if;
    insert into publish_checks(origin, origin_id, firm_id, section, kind, field, item, outcome, reason, target_table, target_id)
    values ('submission', rec.sub, p_firm, 'funds', 'record', fld, rec.r, outc, why, 'firms', p_firm);
  end if;
  if fa is not null then
    fld := 'fund_assets'; amt := fa; ccy := 'USD';
    select * into pick from public._money_pick_source(p_firm, fld, public._rec_sources(rec.sub, rec.r), coalesce(rec.r->>'as_of', v->>'as_of'));
    if pick.reason is null then why := public._place_money_source(p_firm, fld, amt, ccy, pick.url, pick.source_date);
    else why := pick.reason; end if;
    outc := case when why is null then 'published' else 'blocked' end;
    if why is null then n := n + 1;
    else insert into public.money_home_blocked(table_name, op, firm_id, label, value, routed_to, reason)
      values ('research_submissions', 'route', p_firm, 'Fund assets', left(amt::text || ' ' || ccy, 500), null, why); end if;
    insert into publish_checks(origin, origin_id, firm_id, section, kind, field, item, outcome, reason, target_table, target_id)
    values ('submission', rec.sub, p_firm, 'funds', 'record', fld, rec.r, outc, why, 'firms', p_firm);
  end if;
  if n > 0 then delete from firm_page_cache where firm_id = p_firm; end if;
  return n;
end $fn$;

revoke all on function public._firm_host_match(uuid, text) from public, anon, authenticated;
revoke all on function public._money_source_date(text) from public, anon, authenticated;
revoke all on function public._money_source_level(uuid, text) from public, anon, authenticated;
revoke all on function public._money_source_reason(uuid, text, text) from public, anon, authenticated;
revoke all on function public._money_pick_source(uuid, text, jsonb, text) from public, anon, authenticated;
revoke all on function public._place_money_source(uuid, text, numeric, text, text, date) from public, anon, authenticated;
revoke all on function public._firm_money_tiles(uuid) from public, anon, authenticated;
