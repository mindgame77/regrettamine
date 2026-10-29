-- Fix 3: one home per field. A firm has one AUM and one Fund assets, stored only in
-- firms.aum_amount/aum_currency and firms.fund_assets_amount/fund_assets_currency.
-- New firm_profile_facts, vc_source_facts, list_items or timeline_events rows that carry AUM, regulatory AUM,
-- RAUM, gross assets or fund assets under another label are not stored. A clean full number plus currency is
-- routed to the firm column when that column is empty; every blocked row is logged with its reason in money_home_blocked.
-- Existing rows are kept (no deletes). Rollback: supabase/rollbacks/20261029280000_fix3_one_home_aum_rollback.sql

create table if not exists public.money_home_blocked (
  id bigserial primary key,
  created_at timestamptz not null default now(),
  table_name text not null,
  op text not null,
  firm_id uuid,
  label text,
  value text,
  routed_to text,
  reason text not null
);
alter table public.money_home_blocked enable row level security;
revoke all on public.money_home_blocked from anon, authenticated;

-- A label that names AUM / RAUM / gross assets / fund assets. Labels only, never free narrative text.
create or replace function public._money_home_label(t text) returns boolean
language sql immutable set search_path to 'public' as $$
  select coalesce(lower(btrim(regexp_replace(regexp_replace(t, '([a-z])([A-Z])', '\1 \2', 'g'), '[_\-]+', ' ', 'g')))
    ~ '^((regulatory )?(aum|raum)|(regulatory )?assets( under management)?|regulatory assets|(total |fund |private fund )?gross assets?( value)?|(total )?fund assets|(private fund )?gav|item 5f.*)( ?\(.*\))?( usd)?$', false)
$$;

-- Which home: fund assets for gross-assets style labels, otherwise AUM.
create or replace function public._money_home_kind(t text) returns text
language sql immutable set search_path to 'public' as $$
  select case when lower(regexp_replace(coalesce(t, ''), '[_\-]+', ' ', 'g')) ~ '(gross asset|fund assets|gav)' then 'fund_assets' else 'aum' end
$$;

-- A clean full number plus currency from label-like text ("RAUM 160,242,886,816 USD", "$160242886816").
-- Short forms ($7.8B, 160.2 billion) are never parsed: returns no row.
create or replace function public._money_home_full(t text, out amount numeric, out currency text)
language plpgsql immutable set search_path to 'public' as $$
declare m text[];
begin
  m := regexp_match(coalesce(t, ''), '(\$|USD |EUR |GBP |CHF )?\s?(\d{1,3}(?:,\d{3}){2,}|\d{7,})(\.\d+)?(\s*(?:[KkMmBb]n?|[Mm]illion|[Bb]illion|[Tt]housand|[Tt]rillion)\M)?\s*([A-Z]{3}\M)?');
  if m is null or m[4] is not null then return; end if;
  currency := coalesce(m[5], nullif(btrim(m[1]), '$'), case when m[1] = '$' then 'USD' end);
  if currency is null or not public._money_iso(currency) then currency := null; return; end if;
  amount := replace(m[2], ',', '')::numeric;
end $$;

-- The label an upload item uses for AUM / fund assets, if any (used by the entry check).
create or replace function public._money_home_item(rec jsonb, f jsonb) returns text
language sql immutable set search_path to 'public' as $$
  select x from (
    select rec->>'field_path' x, 0 o
    union all select v->>k, 1 from (select rec->'value' v union all select f) s(v), unnest(array['label', 'field', 'kind', 'name', 'hero_label', 'group_key']) k
     where jsonb_typeof(v) = 'object'
    union all select k, 2 from (select rec->'value' v union all select f) s(v), jsonb_object_keys(case when jsonb_typeof(v) = 'object' then v else '{}' end) k
     where k ~* '^(aum|raum|regulatory_aum|regulatoryAum|assets_under_management|fund_assets|fundAssets|total_gross_assets|private_fund_gav)(_[a-z]{3})?$'
  ) z where x is not null and (o = 2 or public._money_home_label(x)) order by o limit 1
$$;

-- Guard on the four fact tables. Blocked rows return NULL so a batch keeps going; the reason is logged.
create or replace function public._money_home_guard() returns trigger
language plpgsql security definer set search_path to 'public' as $$
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
  insert into public.money_home_blocked(table_name, op, firm_id, label, value, routed_to, reason)
  values (tg_table_name, tg_op, fid, left(lbl, 200), left(val, 500), routed,
          'One home per field (fix 3): ' || case when k = 'aum' then 'AUM' else 'Fund assets' end
          || ' is stored only in firms.' || k || '_amount/' || k || '_currency, not as a ' || tg_table_name || ' row labelled "' || left(lbl, 60) || '". Row not stored; ' || why || '.');
  return null;
end $$;
revoke all on function public._money_home_guard() from public, anon, authenticated;

drop trigger if exists money_home_guard on public.firm_profile_facts;
create trigger money_home_guard before insert or update of label, hero_label on public.firm_profile_facts
  for each row execute function public._money_home_guard();
drop trigger if exists money_home_guard on public.vc_source_facts;
create trigger money_home_guard before insert or update of fact_type, value on public.vc_source_facts
  for each row execute function public._money_home_guard();
drop trigger if exists money_home_guard on public.list_items;
create trigger money_home_guard before insert or update of group_key, name on public.list_items
  for each row execute function public._money_home_guard();
drop trigger if exists money_home_guard on public.timeline_events;
create trigger money_home_guard before insert or update of kind, body on public.timeline_events
  for each row execute function public._money_home_guard();

-- Promote: the latest checked "aum" record goes to the firm columns (add-only: an existing value is kept).
create or replace function public._route_aum_record(p_firm uuid, qid text) returns integer
language plpgsql security definer set search_path to 'bots', 'public' as $$
declare rec record; v jsonb; a numeric; c text; fa numeric; n int := 0; why text;
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
  if a is not null and (a < 1000 or a <> trunc(a)) then a := null; end if;   -- A15.8: full numbers only
  if fa is not null and (fa < 1000 or fa <> trunc(fa)) then fa := null; end if;
  if a is not null then
    update firms set aum_amount = a, aum_currency = c where id = p_firm and aum_amount is null;
    if found then n := n + 1; why := null; else why := 'firm already has an AUM in firms.aum_amount; kept the existing value (fix 3)'; end if;
    insert into publish_checks(origin, origin_id, firm_id, section, kind, field, item, outcome, reason, target_table, target_id)
    values ('submission', rec.sub, p_firm, 'funds', 'record', 'aum', rec.r, case when why is null then 'published' else 'rejected' end, why, 'firms', p_firm);
  end if;
  if fa is not null then
    update firms set fund_assets_amount = fa, fund_assets_currency = 'USD' where id = p_firm and fund_assets_amount is null;
    if found then n := n + 1; end if;
  end if;
  if n > 0 then delete from firm_page_cache where firm_id = p_firm; end if;
  return n;
end $$;
revoke all on function public._route_aum_record(uuid, text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.promote_bot_facts(p_firm uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'bots', 'public'
AS $function$
declare qid text := _firm_queue_id(p_firm); k record; rec record; fid uuid; n int := 0;
  hv text; v text; xr text; hl text; src jsonb; sid uuid; i int;
begin
  if qid is null then return 0; end if;
  -- check history is kept: nothing is deleted from publish_checks
  -- Fix 3: AUM no longer becomes a profile card; it goes to its one home (firms.aum_amount / fund_assets_amount).
  n := n + public._route_aum_record(p_firm, qid);
  for k in select * from (values ('hq', 'overview', 'Headquarters', 'HQ', array['HQ'], 0)) t(fp, sec, lbl, hl, same, so) loop
    -- never compete with a curated (non-promoted) card of the same kind
    continue when exists (select 1 from firm_profile_facts where firm_id = p_firm and hero_label = any(k.same) and origin is null);
    select s.id sub, r.value r into rec from research_submissions s, jsonb_array_elements(coalesce(s.payload->'records', '[]')) r
     where s.registry_id = qid and s.valid and r->>'field_path' = k.fp
       and exists (select 1 from jsonb_array_elements(public._rec_sources(s.id, r)) x where coalesce(x->>'url', '') like 'http%' and public._promo_src_ok(x->>'url'))
     order by s.received_at desc, s.id desc limit 1;
    fid := md5('promoted:' || p_firm || ':' || k.fp)::uuid;
    continue when _is_locked_any(fid, p_firm);  -- locked or removed by a cleanup
    if rec.sub is null then continue; /* add-only: never delete */ end if;
    hl := k.hl;
    if k.fp = 'hq' then
      hv := coalesce(rec.r->'value'->>'city', rec.r->>'value'); v := coalesce(rec.r->'value'->>'address', hv);
    else
      hv := case when jsonb_typeof(rec.r->'value'->'amount_usd') = 'number' then _promo_money(rec.r->'value')
                 when jsonb_typeof(rec.r->'value'->'raum_usd') = 'number' then _promo_money(jsonb_build_object('amount_usd', rec.r->'value'->'raum_usd')) end;
      if jsonb_typeof(rec.r->'value'->'amount_usd') is distinct from 'number' and jsonb_typeof(rec.r->'value'->'raum_usd') = 'number' then hl := 'Regulatory AUM'; end if;  -- press_aum text has no cited URL: hide
      v := hv || coalesce(' · ' || (rec.r->'value'->>'basis'), '');
    end if;
    xr := coalesce(_data_rule(k.sec, 'record', jsonb_build_object('label', k.lbl, 'value', v),
                   (select x->>'url' from jsonb_array_elements(public._rec_sources(rec.sub, rec.r)) x
                     where coalesce(x->>'url', '') like 'http%' and public._promo_src_ok(x->>'url') limit 1)),
                   _note_text(v, 400), _note_text(hv, 60));
    if rec.sub is not null and xr is not null then
      insert into publish_checks(origin, origin_id, firm_id, section, kind, field, item, outcome, reason)
      values ('submission', rec.sub, p_firm, k.sec, 'record', k.fp, rec.r, 'rejected', xr);
      hv := null;
    end if;
    if nullif(trim(hv), '') is null then continue; /* add-only: never delete */ end if;
    if _removed_match(p_firm, k.sec, v, null) is not null then
      insert into publish_checks(origin, origin_id, firm_id, section, kind, field, item, outcome, reason)
      values ('submission', rec.sub, p_firm, k.sec, 'record', k.fp, rec.r, 'rejected', _removed_match(p_firm, k.sec, v, null));
      continue;
    end if;
    -- keep the old value so a batch undo can put it back; record a new card as added by this batch
    if exists (select 1 from firm_profile_facts where id = fid) then
      if exists (select 1 from firm_profile_facts where id = fid and origin like 'promoted from submission %' and value is distinct from left(v, 400)) then
        insert into cleanup_backup(batch, firm_id, table_name, row_id, row_data)
        select 'publish:' || coalesce(nullif(current_setting('app.publish_batch', true), ''), 'none'), p_firm, 'firm_profile_facts', fid, to_jsonb(x) from firm_profile_facts x where id = fid;
      end if;
    else
      insert into enrichment_rows(firm_id, table_name, row_id, enrichment_id) values (p_firm, 'firm_profile_facts', fid, rec.sub) on conflict do nothing;
    end if;
    insert into publish_checks(origin, origin_id, firm_id, section, kind, field, item, outcome, reason, target_table, target_id)
    values ('submission', rec.sub, p_firm, k.sec, 'record', k.fp, rec.r, 'published', null, 'firm_profile_facts', fid);
    insert into firm_profile_facts(id, firm_id, section, label, value, hero_label, hero_value, sort_order, origin)
    values (fid, p_firm, k.sec, k.lbl, left(v, 400), hl, left(hv, 60), k.so, 'promoted from submission ' || rec.sub)
    on conflict (id) do update set value = excluded.value, hero_label = excluded.hero_label, hero_value = excluded.hero_value, origin = excluded.origin
      where firm_profile_facts.origin like 'promoted from submission %';
    update firm_profile_facts set last_checked_at = now(),
           checked_source = (select x->>'url' from jsonb_array_elements(public._rec_sources(rec.sub, rec.r)) x
                              where coalesce(x->>'url', '') like 'http%' and public._promo_src_ok(x->>'url') limit 1)
     where id = fid and firm_id = p_firm and origin = 'promoted from submission ' || rec.sub;
    i := 0;
    for src in select x from jsonb_array_elements(public._rec_sources(rec.sub, rec.r)) x where coalesce(x->>'url', '') like 'http%' and public._promo_src_ok(x->>'url') loop
      insert into sources(url, domain, publisher, retrieved_at, data_status, source_system)
      values (src->>'url', substring(src->>'url' from '://(?:www\.)?([^/]+)'), substring(src->>'url' from '://(?:www\.)?([^/]+)'),
              coalesce((src->>'retrieved_at')::timestamptz, now()), 'real', 'bot_promotion')
      on conflict (url) do nothing;
      select id into sid from sources where url = src->>'url';
      insert into fact_sources(id, source_id, firm_id, fact_type, fact_id, label, date_label, sort_order, data_status)
      values (md5(fid || ':' || (src->>'url'))::uuid, sid, p_firm, 'firm_profile_facts', fid,
              substring(src->>'url' from '://(?:www\.)?([^/]+)'), src->>'retrieved_at', i, 'real')
      on conflict (id) do nothing;
      i := i + 1;
    end loop;
    n := n + 1;
  end loop;
  perform _section_count_check(p_firm, 'promote_bot_facts');
  return n;
end $function$;

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
    -- 5c) A15.8 money: full number plus currency, never short forms (same rules as research-ingest moneyChecks)
    r := r || public._money_problems(rec->>'field_path', rec->'value');
    -- 5d) fix 3, one home per field: AUM / RAUM / fund assets only in the aum record (same rule as research-ingest homeChecks)
    if coalesce(rec->>'field_path', '') <> 'aum' and public._money_home_item(rec, it.f) is not null then
      r := r || ('AUM and fund assets have one home: send them only as field_path "aum" (amount_usd, raum_usd, private_fund_gav_usd, or amount + currency), not as "'
                 || left(public._money_home_item(rec, it.f), 40) || '" (fix 3)')::text;
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
end $function$;
