-- Fix 4 (B6d.6): lab tile order is latest fund, then AUM, then Fund assets. AUM and Fund assets come only from
-- firms.aum_amount/aum_currency and firms.fund_assets_amount/fund_assets_currency, and each tile needs a Form ADV
-- (SEC adviser record) source link: never a DEF 14A, a press release, or another non-ADV page. No link = no tile.

-- A Form ADV / SEC adviser-record link: adviserinfo.sec.gov (IAPD, ADV reports and files), or a sec.gov page whose
-- path is a Form ADV page. Never a proxy statement (DEF 14A) or a press release.
create or replace function public._adv_source_ok(p_url text)
returns boolean language sql immutable set search_path to 'public' as $$
  select coalesce(p_url ~* '^https://([a-z0-9-]+\.)*adviserinfo\.sec\.gov(/|$)'
      or p_url ~* '^https://(www\.)?sec\.gov/[^?#]*(form-?adv|/adv[-_/]|iapd)', false)
     and coalesce(p_url !~* '(def[ _-]?14a|press[ _-]?release|/news/|/newsroom/|/litigation/)', false) $$;

alter table public.firms add column if not exists aum_source_url text,
                         add column if not exists fund_assets_source_url text;
alter table public.firms
  add constraint firms_aum_source_adv check (aum_source_url is null or public._adv_source_ok(aum_source_url)),
  add constraint firms_fund_assets_source_adv check (fund_assets_source_url is null or public._adv_source_ok(fund_assets_source_url));
comment on column public.firms.aum_source_url is 'Fix 4 (B6d.6): Form ADV link for aum_amount. The AUM tile needs it.';
comment on column public.firms.fund_assets_source_url is 'Fix 4 (B6d.6): Form ADV link for fund_assets_amount. The Fund assets tile needs it.';

-- The two money tiles for the 10 lab firms: only a stored full amount with a Form ADV link. Else null (tile hidden).
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

CREATE OR REPLACE FUNCTION public.firm_page(p_slug text, p_anon uuid, p_spend boolean DEFAULT false, p_email text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare f firms; u json; open boolean; secs jsonb := '[]'; s page_sections; it jsonb; hero jsonb; q research_queue; qid text;
  vq text; vs timestamptz; hq text; web text; assets text;
begin
  select * into f from firms where slug = p_slug and deleted_at is null and published and not coalesce(is_test, false) and data_status = 'real';
  if f.id is null then return json_build_object('status', 'not_found'); end if;
  u := unlock_firm(p_slug, p_anon, p_spend, p_email);
  open := u->>'status' = 'ok';
  if u->>'status' not in ('ok', 'locked') then return u; end if;
  qid := _firm_queue_id(f.id);
  if qid is not null then select * into q from research_queue where registry_id = qid; end if;
  hq := coalesce(nullif(btrim(f.hq), ''), public.firm_hq_format(q.hq_city, q.state, q.country));
  web := public._firm_website(f.id, f.primary_domain);
  assets := public._firm_assets(f.id);
  if not open then
    select coalesce(jsonb_agg(jsonb_build_object('label', hero_label, 'value', hero_value, 'anchor', section, 'src', _src('firm_profile_facts', id)) order by section desc, sort_order), '[]') into hero
      from firm_profile_facts where firm_id = f.id and not hidden and hero_label is not null and exists (select 1 from fact_sources where fact_type = 'firm_profile_facts' and fact_id = firm_profile_facts.id);
    vq := case when public._visitor_checking(q) then 'claimed' when q.status = 'claimed' then 'queued' else q.status end;
    vs := case when public._visitor_checking(q) then q.claimed_at end;
    if not f.indexable and jsonb_array_length(hero) = 0 then
      select coalesce(jsonb_agg(jsonb_build_object('label', l, 'value', v, 'anchor', 'overview', 'src', '[]'::jsonb) order by o), '[]') into hero
        from (values (1, 'HQ', hq), (2, 'SEC CRD', nullif(q.sec_crd, '')), (3, 'LEI', nullif(q.lei, ''))) x(o, l, v) where v is not null;
    end if;
    return json_build_object('status', 'ok', 'open', false, 'locked', u->>'status', 'unchecked', not f.indexable,
      'firm', json_build_object('slug', f.slug, 'name', coalesce(f.display_name, f.name), 'sec_name', coalesce(f.legal_name, f.name), 'short_name', f.short_name, 'hq', hq, 'website', web, 'assets', assets, 'social', public._firm_social(f.id), 'founded_year', f.founded_year, 'money', public._firm_money_tiles(f.id)),
      'hero', hero, 'sections', '[]'::json, 'done', _firm_checks_done(f.id),
      'checks', (select json_agg(json_build_object('n', e->'n', 'title', e->'title', 'descr', e->'descr', 'state', null, 'count', null, 'searched_at', null, 'items', null, 'itemized', null, 'name_only', null)) from json_array_elements(public._check_placeholders()) e),
      'queue', vq, 'started_at', vs, 'details', null, 'outline', null, 'ondemand', _ondemand_view(f.id, p_anon), 'activity', public._firm_activity(f.id, open));
  end if;
  for s in select * from page_sections where enabled order by sort_order loop
    it := _sec_items(s.key, f.id);
    continue when jsonb_array_length(it) = 0;
    secs := secs || jsonb_build_object('key', s.key, 'title', s.title, 'subtitle', s.subtitle, 'renderer', s.renderer,
      'count', jsonb_array_length(it), 'unit', case when jsonb_array_length(it) = 1 then s.unit_one else s.unit_many end,
      'teaser', it->0->>'head', 'items', it);
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('label', hero_label, 'value', hero_value, 'anchor', section, 'src', _src('firm_profile_facts', id)) order by section desc, sort_order), '[]') into hero
    from firm_profile_facts where firm_id = f.id and not hidden and hero_label is not null and exists (select 1 from fact_sources where fact_type = 'firm_profile_facts' and fact_id = firm_profile_facts.id);
  vq := case when public._visitor_checking(q) then 'claimed' when q.status = 'claimed' then 'queued' else q.status end;
  vs := case when public._visitor_checking(q) then q.claimed_at end;
  return json_build_object('status', 'ok', 'open', true, 'unchecked', false, 'done', _firm_checks_done(f.id),
    'firm', json_build_object('slug', f.slug, 'name', coalesce(f.display_name, f.name), 'sec_name', coalesce(f.legal_name, f.name), 'short_name', f.short_name, 'hq', hq, 'website', web, 'assets', assets, 'social', public._firm_social(f.id), 'founded_year', f.founded_year, 'money', public._firm_money_tiles(f.id)),
    'hero', hero, 'sections', secs,
    'checks', public._firm_checks(f.id),
    'queue', vq, 'started_at', vs, 'details', u->'details', 'outline', null, 'ondemand', _ondemand_view(f.id, p_anon), 'activity', public._firm_activity(f.id, open));
end $function$
;

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

delete from public.firm_page_cache where firm_id in (select id from public.firms where public._lab_firm(id));
