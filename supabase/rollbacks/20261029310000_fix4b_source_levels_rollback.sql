-- Rollback fix 4b. Restores the fix 4 tile helper and _route_aum_record, and the fix 3b money-home guard.
-- Drops the source-level helpers. Level and date columns are dropped. A non-ADV AUM link, if one was stored
-- after this fix, is cleared so the Form ADV check can be put back. Amounts already stored are kept.
-- firm_page is unchanged by fix 4b, so it is not restored here.

create or replace function public._firm_money_tiles(p_firm uuid)
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select case when public._lab_firm(f.id) then nullif(jsonb_strip_nulls(jsonb_build_object(
    'aum', case when f.aum_amount is not null and public._adv_source_ok(f.aum_source_url) then jsonb_build_object(
             'amount', f.aum_amount, 'currency', f.aum_currency, 'display', public._money_display(f.aum_amount, f.aum_currency),
             'url', f.aum_source_url) end,
    'fund_assets', case when f.fund_assets_amount is not null and public._adv_source_ok(f.fund_assets_source_url) then jsonb_build_object(
             'amount', f.fund_assets_amount, 'currency', f.fund_assets_currency,
             'display', public._money_display(f.fund_assets_amount, f.fund_assets_currency), 'url', f.fund_assets_source_url) end)), '{}'::jsonb) end
    from firms f where f.id = p_firm $$;

CREATE OR REPLACE FUNCTION public._route_aum_record(p_firm uuid, qid text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'bots', 'public'
AS $function$
declare rec record; v jsonb; a numeric; c text; fa numeric; n int := 0; why text; adv text;
begin
  if qid is null then return 0; end if;
  select s.id sub, r.value r into rec from research_submissions s, jsonb_array_elements(coalesce(s.payload->'records', '[]')) r
   where s.registry_id = qid and s.valid and r->>'field_path' = 'aum'
     and exists (select 1 from jsonb_array_elements(public._rec_sources(s.id, r)) x where coalesce(x->>'url', '') like 'http%' and public._promo_src_ok(x->>'url'))
   order by s.received_at desc, s.id desc limit 1;
  if rec.sub is null then return 0; end if;
  v := rec.r->'value';
  -- Fix 4: the record's Form ADV link, stored with the amount (no link = the tile stays hidden)
  select x->>'url' into adv from jsonb_array_elements(public._rec_sources(rec.sub, rec.r)) x
   where public._adv_source_ok(x->>'url') limit 1;
  if jsonb_typeof(v) <> 'object' then return 0; end if;
  if lower(coalesce(v->>'basis', '')) = 'press' then return 0; end if;  -- A7.3
  if jsonb_typeof(v->'amount_usd') = 'number' then a := (v->>'amount_usd')::numeric; c := 'USD';
  elsif jsonb_typeof(v->'amount') = 'number' and public._money_iso(upper(v->>'currency')) then a := (v->>'amount')::numeric; c := upper(v->>'currency');
  elsif jsonb_typeof(v->'raum_usd') = 'number' then a := (v->>'raum_usd')::numeric; c := 'USD';
  end if;
  if jsonb_typeof(v->'private_fund_gav_usd') = 'number' then fa := (v->>'private_fund_gav_usd')::numeric; end if;
  if a is not null and (a < 1000 or a <> trunc(a)) then a := null; end if;   -- A15.8: full numbers only
  if fa is not null and (fa < 1000 or fa <> trunc(fa)) then fa := null; end if;
  if a is not null then
    update firms set aum_amount = a, aum_currency = c, aum_source_url = adv where id = p_firm and aum_amount is null;
    if found then n := n + 1; why := null; else why := 'firm already has an AUM in firms.aum_amount; kept the existing value (fix 3)'; end if;
    insert into publish_checks(origin, origin_id, firm_id, section, kind, field, item, outcome, reason, target_table, target_id)
    values ('submission', rec.sub, p_firm, 'funds', 'record', 'aum', rec.r, case when why is null then 'published' else 'rejected' end, why, 'firms', p_firm);
  end if;
  if fa is not null then
    update firms set fund_assets_amount = fa, fund_assets_currency = 'USD', fund_assets_source_url = adv where id = p_firm and fund_assets_amount is null;
    if found then n := n + 1; end if;
  end if;
  if n > 0 then delete from firm_page_cache where firm_id = p_firm; end if;
  return n;
end $function$
;

CREATE OR REPLACE FUNCTION public._money_home_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare lbl text; val text; k text; a numeric; c text; fid uuid; routed text; why text; done int;
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
  else -- timeline_events: the kind, or a "Label: value" style body
    lbl := case when public._money_home_label(new.kind) then new.kind
                when public._money_home_label(substring(new.body from '^\s*([^:·—]{2,40}?)\s*[:·—]')) then substring(new.body from '^\s*([^:·—]{2,40}?)\s*[:·—]') end;
    if tg_op = 'UPDATE' and (public._money_home_label(old.kind) or public._money_home_label(substring(old.body from '^\s*([^:·—]{2,40}?)\s*[:·—]'))) then return new; end if;
    val := new.body;
  end if;
  if lbl is null then return new; end if;
  k := public._money_home_kind(lbl);
  select amount, currency into a, c from public._money_home_full(val);
  -- Per-fund gross assets ("Fund gross assets") are not the firm total: never routed.
  if a is null or fid is null or (k = 'fund_assets' and lower(lbl) !~ '^(total |private fund )?(fund assets|gross assets|gav|private fund gav)') then
    why := 'no full number plus currency code for the firm total, so nothing was routed';
  elsif k = 'aum' then
    update public.firms set aum_amount = a, aum_currency = c where id = fid and aum_amount is null;
    get diagnostics done = row_count;
    if done > 0 then routed := 'firms.aum_amount'; why := 'routed to firms.aum_amount/aum_currency';
    else why := 'firm already has an AUM in firms.aum_amount; kept the existing value'; end if;
  else
    update public.firms set fund_assets_amount = a, fund_assets_currency = c where id = fid and fund_assets_amount is null;
    get diagnostics done = row_count;
    if done > 0 then routed := 'firms.fund_assets_amount'; why := 'routed to firms.fund_assets_amount/fund_assets_currency';
    else why := 'firm already has Fund assets in firms.fund_assets_amount; kept the existing value'; end if;
  end if;
  if routed is not null then delete from public.firm_page_cache where firm_id = fid; end if;
  insert into public.money_home_blocked(table_name, op, firm_id, label, value, routed_to, reason, row_id)
  values (tg_table_name, tg_op, fid, left(lbl, 200), left(val, 500), routed,
          'One home per field (fix 3): ' || case when k = 'aum' then 'AUM' else 'Fund assets' end
          || ' is stored only in firms.' || k || '_amount/' || k || '_currency, not as a ' || tg_table_name || ' row labelled "' || left(lbl, 60) || '". Row not stored; ' || why || '.', new.id);
  return null;
end $function$
;

drop function if exists public._place_money_source(uuid, text, numeric, text, text, date);
drop function if exists public._money_pick_source(uuid, text, jsonb, text);
drop function if exists public._money_source_reason(uuid, text, text);
drop function if exists public._money_source_level(uuid, text);
drop function if exists public._money_source_date(text);
drop function if exists public._firm_host_match(uuid, text);

alter table public.firms drop constraint if exists firms_aum_source_ok;
alter table public.firms drop constraint if exists firms_aum_source_level_chk;
alter table public.firms drop constraint if exists firms_fund_assets_source_level_chk;
update public.firms set aum_source_url = null
 where aum_source_url is not null and not public._adv_source_ok(aum_source_url);
alter table public.firms drop constraint if exists firms_aum_source_adv;
alter table public.firms
  add constraint firms_aum_source_adv check (aum_source_url is null or public._adv_source_ok(aum_source_url));
alter table public.firms
  drop column if exists aum_source_level,
  drop column if exists aum_source_date,
  drop column if exists fund_assets_source_level,
  drop column if exists fund_assets_source_date;

comment on column public.firms.aum_source_url is 'Fix 4 (B6d.6): Form ADV link for aum_amount. The AUM tile needs it.';
comment on column public.firms.fund_assets_source_url is 'Fix 4 (B6d.6): Form ADV link for fund_assets_amount. The Fund assets tile needs it.';
