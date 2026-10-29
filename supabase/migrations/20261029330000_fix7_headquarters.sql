-- Fix 7: Headquarters has one home on the firm. City, region, and country (ISO 3166 alpha-2),
-- plus the source link, source level, and source date.
-- Level 1 is the SEC Form ADV principal office (adviserinfo.sec.gov or a sec.gov Form ADV page).
-- Level 2 is the firm's own website (the link host matches the firm's domain).
-- Level 3 is a national company register (Companies House) or a trusted page.
-- A higher level replaces a lower one. The same level replaces only when its source date is newer.
-- Anything else is blocked and logged with a reason, the fix 3b way.
-- No existing Headquarters row is copied, updated, or deleted. firm_page still reads the old HQ text.
-- Rollback: supabase/rollbacks/20261029330000_fix7_headquarters_rollback.sql

alter table public.firms
  add column if not exists hq_city text,
  add column if not exists hq_region text,
  add column if not exists hq_country text,
  add column if not exists hq_source_url text,
  add column if not exists hq_source_level smallint,
  add column if not exists hq_source_date date;

comment on column public.firms.hq_city is 'Headquarters city. One home for HQ (fix 7). Not filled from the old Headquarters rows.';
comment on column public.firms.hq_region is 'Headquarters state or region. Not shown on its own.';
comment on column public.firms.hq_country is 'Headquarters country, ISO 3166 alpha-2. Check 8 reads this when it is set. Not filled from the old Headquarters rows.';
comment on column public.firms.hq_source_url is 'Link for the headquarters. Level 1 Form ADV, level 2 the firm site, level 3 a company register or a trusted page.';
comment on column public.firms.hq_source_level is '1 Form ADV, 2 the firm site, 3 a national company register or a trusted page. Not shown on the page.';
comment on column public.firms.hq_source_date is 'Date of the headquarters source. The same level replaces the stored value only when this date is newer.';

create or replace function public._hq_label(t text)
returns boolean language sql immutable set search_path to 'public' as $fn$
  select lower(btrim(coalesce(t, ''))) in ('hq', 'headquarters', 'headquarter')
$fn$;

-- ISO 3166 alpha-2. A full country name is accepted only for the US and the UK. Anything else must already be two letters.
create or replace function public._hq_iso(p text)
returns text language plpgsql immutable set search_path to 'public' as $fn$
declare s text := upper(btrim(coalesce(p, '')));
begin
  if s = '' then return null; end if;
  if s in ('US', 'USA', 'U.S.', 'U.S.A.', 'UNITED STATES', 'UNITED STATES OF AMERICA') then return 'US'; end if;
  if s in ('GB', 'UK', 'U.K.', 'UNITED KINGDOM', 'GREAT BRITAIN') then return 'GB'; end if;
  if s ~ '^[A-Z]{2}$' then return s; end if;
  return null;
end $fn$;

create or replace function public._hq_register(p_url text)
returns boolean language sql immutable set search_path to 'public' as $fn$
  select coalesce(public._dom(p_url) ~ '(^|\.)(companieshouse\.gov\.uk|company-information\.service\.gov\.uk)$', false)
$fn$;

create or replace function public._hq_trusted(p_url text)
returns boolean language sql stable security definer set search_path to 'public' as $fn$
  select exists (
    select 1 from public.trusted_source_domains t
     where public._dom(p_url) = t.domain or public._dom(p_url) like '%.' || t.domain)
$fn$;

-- 1 Form ADV, 2 the firm's own site, 3 a company register or a trusted page. p_dom is used when the firm id is not known yet.
create or replace function public._hq_source_level(p_firm uuid, p_url text, p_dom text)
returns smallint language plpgsql stable security definer set search_path to 'public' as $fn$
declare dom text := nullif(regexp_replace(lower(coalesce(p_dom, '')), '^www\.', ''), '');
begin
  if p_url is null or p_url !~* '^https://' then return null; end if;
  if public._adv_source_ok(p_url) then return 1; end if;
  if p_firm is not null and public._firm_host_match(p_firm, p_url) then return 2; end if;
  if p_firm is null and dom is not null and dom <> ''
     and (public._dom(p_url) = dom or public._dom(p_url) like '%.' || dom) then return 2; end if;
  if public._hq_register(p_url) or public._hq_trusted(p_url) then return 3; end if;
  return null;
end $fn$;

alter table public.firms drop constraint if exists firms_hq_country_chk;
alter table public.firms drop constraint if exists firms_hq_source_level_chk;
alter table public.firms drop constraint if exists firms_hq_source_url_chk;
alter table public.firms
  add constraint firms_hq_country_chk check (hq_country is null or hq_country ~ '^[A-Z]{2}$'),
  add constraint firms_hq_source_level_chk check (hq_source_level is null or hq_source_level in (1, 2, 3)),
  add constraint firms_hq_source_url_chk check (
    hq_source_url is null
    or (hq_source_level is not null and public._hq_source_level(id, hq_source_url, null) = hq_source_level));

-- City, region, and country from a record object or a checker item. Free text is not parsed into a country.
create or replace function public._hq_parts(p jsonb, out city text, out region text, out country text)
language plpgsql immutable set search_path to 'public' as $fn$
declare v jsonb := case when jsonb_typeof(p->'value') = 'object' then p->'value' else p end;
begin
  city := nullif(left(btrim(coalesce(v->>'city', p->>'city', '')), 120), '');
  region := nullif(left(btrim(coalesce(v->>'region', v->>'state', p->>'region', p->>'state', '')), 120), '');
  country := public._hq_iso(coalesce(v->>'country', p->>'country'));
end $fn$;

create or replace function public._place_hq(p_firm uuid, p_city text, p_region text, p_country text, p_url text, p_date date)
returns text language plpgsql security definer set search_path to 'public' as $fn$
declare lvl smallint; cur_lvl smallint; cur_dt date; cur_country text; done int;
begin
  if p_firm is null then return 'firm not found'; end if;
  if nullif(btrim(coalesce(p_city, '')), '') is null then return 'no city, so nothing was stored'; end if;
  if p_country is null or p_country !~ '^[A-Z]{2}$' then return 'no ISO country code, so nothing was stored'; end if;
  lvl := public._hq_source_level(p_firm, p_url, null);
  if lvl is null then return 'no acceptable source link'; end if;
  select hq_country, hq_source_level, hq_source_date into cur_country, cur_lvl, cur_dt
    from public.firms where id = p_firm for update;
  if not found then return 'firm not found'; end if;
  if cur_country is not null or cur_lvl is not null then
    cur_lvl := coalesce(cur_lvl, 99);
    if lvl > cur_lvl then
      return 'source level ' || lvl || ' is lower than the stored level ' || cur_lvl || '; kept the existing value';
    end if;
    if lvl = cur_lvl and not (p_date is not null and cur_dt is not null and p_date > cur_dt) then
      return 'same source level ' || lvl || ', source date ' || coalesce(p_date::text, 'none')
        || ' is not newer than ' || coalesce(cur_dt::text, 'none') || '; kept the existing value';
    end if;
  end if;
  update public.firms
     set hq_city = left(btrim(p_city), 120),
         hq_region = nullif(left(btrim(coalesce(p_region, '')), 120), ''),
         hq_country = p_country,
         hq_source_url = p_url,
         hq_source_level = lvl,
         hq_source_date = p_date
   where id = p_firm;
  get diagnostics done = row_count;
  if done = 0 then return 'Headquarters was not stored'; end if;
  delete from public.firm_page_cache where firm_id = p_firm;
  return null;
end $fn$;

create or replace function public._place_hq_item(p_firm uuid, p_item jsonb, p_url text, p_as_of text)
returns text language plpgsql security definer set search_path to 'public' as $fn$
declare city text; region text; country text; dt date;
begin
  select x.city, x.region, x.country into city, region, country from public._hq_parts(coalesce(p_item, '{}'::jsonb)) x;
  dt := coalesce(public._money_source_date(p_as_of), public._money_source_date(p_item->>'date'), public._money_source_date(p_item->>'as_of'));
  return public._place_hq(p_firm, city, region, country, p_url, dt);
end $fn$;

create or replace function public._hq_pick_source(p_firm uuid, p_dom text, p_sources jsonb, p_as_of text)
returns table(url text, source_level smallint, source_date date, reason text)
language plpgsql stable security definer set search_path to 'public' as $fn$
declare i int; src jsonb; u text; lvl smallint; dt date; best_u text; best_l smallint; best_d date;
begin
  for i in 0 .. coalesce(jsonb_array_length(p_sources), 0) - 1 loop
    src := p_sources->i;
    u := src->>'url';
    lvl := public._hq_source_level(p_firm, u, p_dom);
    dt := coalesce(public._money_source_date(src->>'published_at'), public._money_source_date(src->>'as_of'),
                   public._money_source_date(p_as_of), public._money_source_date(src->>'retrieved_at'));
    if lvl in (1, 2, 3) and (
         best_u is null or lvl < best_l or (lvl = best_l and dt is not null and (best_d is null or dt > best_d))) then
      best_u := u; best_l := lvl; best_d := dt;
    end if;
  end loop;
  if best_u is not null then
    url := best_u; source_level := best_l; source_date := best_d; reason := null; return next; return;
  end if;
  url := null; source_level := null; source_date := null; reason := 'no acceptable source link'; return next;
end $fn$;

create or replace function public._hq_entry_problem(p_dom text, p_rec jsonb, p_f jsonb, p_url text)
returns text language plpgsql stable security definer set search_path to 'public' as $fn$
declare item jsonb; city text; region text; country text; lvl smallint;
begin
  item := case
    when jsonb_typeof(p_rec->'value') = 'object' then p_rec->'value' || coalesce(p_f, '{}'::jsonb)
    when p_f is not null then p_f || jsonb_strip_nulls(jsonb_build_object('value', p_rec->'value'))
    else coalesce(p_rec, '{}'::jsonb) end;
  select x.city, x.region, x.country into city, region, country from public._hq_parts(item) x;
  if city is null then return 'Headquarters needs a city'; end if;
  if country is null then return 'Headquarters needs an ISO country code'; end if;
  lvl := public._hq_source_level(null, p_url, p_dom);
  if lvl is null then return 'no acceptable source link for Headquarters'; end if;
  return null;
end $fn$;

-- True when hq_country is set and is not US. Null when the field is empty, so check 8 keeps its current result.
create or replace function public._check8_outside_us(p_firm uuid)
returns boolean language sql stable security definer set search_path to 'public' as $fn$
  select case when f.hq_country is null then null when f.hq_country = 'US' then false else true end
    from public.firms f where f.id = p_firm
$fn$;

create or replace function public._hq_home_guard()
returns trigger language plpgsql security definer set search_path to 'public' as $fn$
declare lbl text; val text; fid uuid; src text; src_date text; item jsonb; why text; routed text; reason text;
begin
  fid := new.firm_id;
  if tg_table_name = 'firm_profile_facts' then
    lbl := case when public._hq_label(new.label) then new.label when public._hq_label(new.hero_label) then new.hero_label end;
    if tg_op = 'UPDATE' and (public._hq_label(old.label) or public._hq_label(old.hero_label)) then return new; end if;
    val := concat_ws(' · ', new.hero_value, new.value);
    item := jsonb_build_object('label', lbl, 'value', val);
    src := null; src_date := null;
  elsif tg_table_name = 'vc_source_facts' then
    lbl := case when public._hq_label(new.fact_type) then new.fact_type
                when public._hq_label(new.value->>'field') then new.value->>'field'
                when public._hq_label(new.value->>'label') then new.value->>'label' end;
    if tg_op = 'UPDATE' and (public._hq_label(old.fact_type) or public._hq_label(old.value->>'field') or public._hq_label(old.value->>'label')) then return new; end if;
    val := coalesce(new.value->>'value', new.value->>'city', new.value::text);
    item := coalesce(new.value, '{}'::jsonb);
    src := new.source_url; src_date := new.retrieved_at::text;
  elsif tg_table_name = 'list_items' then
    lbl := case when public._hq_label(new.group_key) then new.group_key when public._hq_label(new.name) then new.name end;
    if tg_op = 'UPDATE' and (public._hq_label(old.group_key) or public._hq_label(old.name)) then return new; end if;
    val := concat_ws(' · ', new.value, new.note);
    item := jsonb_build_object('label', lbl, 'value', val);
    src := null; src_date := null;
  else
    lbl := case when public._hq_label(new.kind) then new.kind
                when public._hq_label(substring(new.body from '^\s*([^:·—]{2,40}?)\s*[:·—]')) then substring(new.body from '^\s*([^:·—]{2,40}?)\s*[:·—]') end;
    if tg_op = 'UPDATE' and (public._hq_label(old.kind) or public._hq_label(substring(old.body from '^\s*([^:·—]{2,40}?)\s*[:·—]'))) then return new; end if;
    val := new.body;
    item := jsonb_build_object('label', lbl, 'value', val);
    src := new.source_url; src_date := new.date_label;
  end if;
  if lbl is null then return new; end if;
  why := public._place_hq_item(fid, item, src, src_date);
  if why is null then routed := 'firms.hq_city'; end if;
  reason := 'One home per field (fix 7): Headquarters is stored only in firms.hq_city, firms.hq_region, and firms.hq_country, not as a '
    || tg_table_name || ' row labelled "' || left(lbl, 60) || '". Row not stored; '
    || coalesce(why, 'routed to firms.hq_city/hq_region/hq_country') || '.';
  insert into public.money_home_blocked(table_name, op, firm_id, label, value, routed_to, reason, row_id)
  values (tg_table_name, left(tg_op, 40), fid, left(lbl, 200), left(coalesce(val, ''), 500), routed, reason, new.id);
  return null;
end $fn$;

drop trigger if exists hq_home_guard on public.firm_profile_facts;
create trigger hq_home_guard before insert or update of label, hero_label on public.firm_profile_facts
  for each row execute function public._hq_home_guard();
drop trigger if exists hq_home_guard on public.vc_source_facts;
create trigger hq_home_guard before insert or update of fact_type, value on public.vc_source_facts
  for each row execute function public._hq_home_guard();
drop trigger if exists hq_home_guard on public.list_items;
create trigger hq_home_guard before insert or update of group_key, name on public.list_items
  for each row execute function public._hq_home_guard();
drop trigger if exists hq_home_guard on public.timeline_events;
create trigger hq_home_guard before insert or update of kind, body on public.timeline_events
  for each row execute function public._hq_home_guard();

create or replace function public._route_hq_record(p_firm uuid, qid text)
returns integer language plpgsql security definer set search_path to 'bots', 'public' as $fn$
declare rec record; item jsonb; pick record; why text; outc text;
begin
  if qid is null or p_firm is null then return 0; end if;
  select s.id sub, r.value r into rec
    from bots.research_submissions s, jsonb_array_elements(coalesce(s.payload->'records', '[]')) r
   where s.registry_id = qid and s.valid and r->>'field_path' in ('hq', 'headquarters')
     and exists (select 1 from jsonb_array_elements(public._rec_sources(s.id, r)) x
                  where coalesce(x->>'url', '') like 'http%' and public._promo_src_ok(x->>'url'))
   order by s.received_at desc, s.id desc limit 1;
  if rec.sub is null then return 0; end if;
  item := case when jsonb_typeof(rec.r->'value') = 'object' then rec.r->'value' else jsonb_build_object('value', rec.r->>'value') end;
  select * into pick from public._hq_pick_source(p_firm, null, public._rec_sources(rec.sub, rec.r), coalesce(rec.r->>'as_of', item->>'as_of'));
  if pick.reason is null then why := public._place_hq_item(p_firm, item, pick.url, coalesce(pick.source_date::text, rec.r->>'as_of'));
  else why := pick.reason; end if;
  outc := case when why is null then 'published' else 'blocked' end;
  if why is not null then
    insert into public.money_home_blocked(table_name, op, firm_id, label, value, routed_to, reason)
    values ('research_submissions', 'route', p_firm, 'Headquarters', left(coalesce(item->>'city', item::text), 500), null,
            'One home per field (fix 7): Headquarters is stored only in firms.hq_city, firms.hq_region, and firms.hq_country. ' || why || '.');
  end if;
  insert into public.publish_checks(origin, origin_id, firm_id, section, kind, field, item, outcome, reason, target_table, target_id)
  values ('submission', rec.sub, p_firm, 'overview', 'record', 'hq', rec.r, outc, why, 'firms', p_firm);
  if why is null then return 1; end if;
  return 0;
end $fn$;

create or replace function public.promote_bot_facts(p_firm uuid)
returns integer language plpgsql security definer set search_path to 'bots', 'public' as $fn$
declare qid text := public._firm_queue_id(p_firm); n int := 0;
begin
  if qid is null then return 0; end if;
  n := n + public._route_aum_record(p_firm, qid);
  n := n + public._route_hq_record(p_firm, qid);
  perform public._section_count_check(p_firm, 'promote_bot_facts');
  return n;
end $fn$;

revoke all on function public._hq_label(text) from public, anon, authenticated;
revoke all on function public._hq_iso(text) from public, anon, authenticated;
revoke all on function public._hq_register(text) from public, anon, authenticated;
revoke all on function public._hq_trusted(text) from public, anon, authenticated;
revoke all on function public._hq_source_level(uuid, text, text) from public, anon, authenticated;
revoke all on function public._hq_parts(jsonb) from public, anon, authenticated;
revoke all on function public._place_hq(uuid, text, text, text, text, date) from public, anon, authenticated;
revoke all on function public._place_hq_item(uuid, jsonb, text, text) from public, anon, authenticated;
revoke all on function public._hq_pick_source(uuid, text, jsonb, text) from public, anon, authenticated;
revoke all on function public._hq_entry_problem(text, jsonb, jsonb, text) from public, anon, authenticated;
revoke all on function public._check8_outside_us(uuid) from public, anon, authenticated;
revoke all on function public._hq_home_guard() from public, anon, authenticated;
revoke all on function public._route_hq_record(uuid, text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public._checker_write(p_firm uuid, p_section text, p_f jsonb, p_url text, p_level smallint, p_check integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rid uuid := gen_random_uuid(); key text; n int := p_check; lab boolean := public._lab_firm(p_firm); acct text; why text;
begin
  key := p_section || '|' || coalesce(nullif(p_url, ''), left(p_f::text, 200));
  if p_section = 'press' then
    insert into press_items(id, publisher, domain, url, published_label, headline, snippet, data_status, retrieved_at, source_system)
    values (rid, coalesce(p_f->>'outlet', public.source_label(public._dom(p_url), p_url)), public._dom(p_url), p_url,
            p_f->>'date', left(coalesce(p_f->>'headline', ''), 400), left(p_f->>'snippet', 600), 'real', now(), 'checker');
    insert into press_item_firms(press_item_id, firm_id, sort_order, check_mark, checked_on, checked_by, source_level)
    values (rid, p_firm, 900, 'checked_correct', case when lab then now() end, case when lab then 'Checker' end, case when lab then p_level end);
  elsif p_section = 'timeline' then
    insert into timeline_events(id, firm_id, date_label, kind, body, sort_order, source_url, check_mark, checked_on, checked_by, source_level)
    values (rid, p_firm, p_f->>'date', 'Reported', left(coalesce(p_f->>'event', ''), 300), 900, p_url, 'checked_correct',
            case when lab then now() end, case when lab then 'Checker' end, case when lab then p_level end);
  elsif p_section = 'people' then
    insert into firm_people_roles(id, firm_id, kind, person_name, role, sort_order, checked_on, checked_by, source_level)
    values (rid, p_firm, coalesce(p_f->>'kind', 'officer'), left(p_f->>'name', 120), left(coalesce(p_f->>'role', ''), 300), 900,
            case when lab then now() end, case when lab then 'Checker' end, case when lab then p_level end);
  elsif p_section = 'social' then
    -- socialAccounts (A2.10 / B3.8): a level-2 media_reach fact like the #263 General Catalyst row. Never firm_profile_facts.
    acct := public._checker_social_platform(p_f->>'platform');
    key := 'social|' || coalesce(p_f->>'url', '');
    insert into vc_source_facts(id, firm_id, fact_type, section, value, source_url, source_label, source_type, retrieved_at, data_status,
                                source_system, external_id, checked_on, checked_by, source_level)
    values (rid, p_firm, 'media_reach', 'media_reach',
            jsonb_build_object('field', 'media_' || acct || '_followers',
                               'value', (p_f->>'followers') || coalesce(' (@' || nullif(substring(p_f->>'url' from '^https?://[^/]+/(?:company/|@)?([^/?#]+)'), '') || ')', ''),
                               'url', p_f->>'url', 'entity', 'firm', 'publisher', initcap(acct),
                               'linked_from', coalesce(nullif(p_f->>'found_on_url', ''), p_url),
                               'linked_checked', coalesce(p_f->>'followers_read_at', to_char(now(), 'YYYY-MM-DD')),
                               'sheet_status', 'firm says'),
            p_f->>'url', initcap(acct), acct,
            coalesce((p_f->>'followers_read_at')::date::timestamptz, now()), 'real', 'checker',
            'checker:social:' || md5(p_firm::text || '|' || acct || '|' || public._checker_url_key(p_f->>'url')),
            case when lab then now() end, case when lab then 'Checker' end, 2);
  elsif p_section in ('overview', 'funds', 'lps') then
    if p_section = 'overview' and public._hq_label(p_f->>'label') then
      why := public._place_hq_item(p_firm, p_f, p_url, coalesce(p_f->>'date', p_f->>'as_of'));
      insert into public.money_home_blocked(table_name, op, firm_id, label, value, routed_to, reason)
      values ('firm_profile_facts', 'checker', p_firm, left(coalesce(p_f->>'label', 'Headquarters'), 200),
              left(coalesce(p_f->>'city', p_f->>'value', ''), 500),
              case when why is null then 'firms.hq_city' else null end,
              'One home per field (fix 7): Headquarters is stored only in firms.hq_city, firms.hq_region, and firms.hq_country, not as a firm_profile_facts row. Row not stored; '
              || coalesce(why, 'routed to firms.hq_city/hq_region/hq_country') || '.');
      return null;
    end if;
    insert into firm_profile_facts(id, firm_id, section, label, value, sort_order, origin, checked_on, checked_by, source_level)
    values (rid, p_firm, p_section,
            case p_section when 'overview' then p_f->>'label' when 'lps' then p_f->>'name' else 'Funds' end,
            left(case p_section when 'overview' then p_f->>'value' when 'lps' then p_f->>'name' else coalesce(p_f->>'name', '') end, 400),
            900, 'checker', case when lab then now() end, case when lab then 'Checker' end, case when lab then p_level end);
  elsif p_section = 'legal' then
    -- Fix 5: an SEC adviser summary is not a regulator action. Do not write it.
    if public._sec_adviser_summary('regulator', coalesce(p_f->>'title', '')) then
      perform public._block_sec_summary(p_firm, 'checker', coalesce(p_f->>'title', ''), null);
      return null;
    end if;
    insert into firm_legal_items(id, firm_id, grp, title, year_label, status_label, sort_order, checked_on, checked_by, source_level)
    values (rid, p_firm, 'context', left(coalesce(p_f->>'title', ''), 300), substring(p_f->>'date' from '^(\d{4})'), p_f->>'status', 900,
            case when lab then now() end, case when lab then 'Checker' end, case when lab then p_level end);
  elsif p_section = 'founders' then
    insert into reviews(id, firm_id, body, first_hand, verification_status, moderation_status, anonymous, author_name, source_urls,
                        review_type, is_public, source_system, dedupe_key, checked_on, checked_by, source_level)
    values (rid, p_firm, left(coalesce(p_f->>'quote', ''), 2000), false, 'unverified', 'approved', false,
            left(p_f->>'who', 200), array[p_url], 'founder', true, 'checker', 'url:' || left(p_url, 400),
            case when lab then now() end, case when lab then 'Checker' end, case when lab then p_level end);
  elsif n is not null then
    insert into vc_source_facts(firm_id, fact_type, section, value, source_url, source_label, retrieved_at, data_status, source_system, external_id,
                                checked_on, checked_by, source_level)
    values (p_firm,
            case when n in (1, 2, 10) then 'sanctions_check' when n in (4, 5) then 'regulatory_record' when n = 8 then 'fund_fact' else 'legal_matter' end,
            'checks',
            jsonb_build_object('field', case n when 1 then 'sanctions' when 2 then 'terrorism_lists' when 3 then 'export_restrictions'
              when 4 then 'regulatory_action' when 5 then 'aml_penalties' when 7 then 'courts_worldwide' when 8 then 'registration_status'
              when 9 then 'people_screen' when 10 then 'pep' else 'legal_matter' end, 'value', left(p_f::text, 500)),
            p_url, 'Checker', now(), 'real', 'checker', 'checker:' || p_firm::text || ':' || n::text || ':' || md5(coalesce(p_url, '') || p_f::text),
            case when lab then now() end, case when lab then 'Checker' end, case when lab then p_level end);
    rid := gen_random_uuid();
  else
    return null;
  end if;
  insert into checker_marks(firm_id, kind, item_key, checked_by, source_level, url)
  values (p_firm, coalesce(p_section, 'check'), key, 'Checker', p_level, p_url)
  on conflict (firm_id, kind, item_key) do nothing;
  return rid;
end $function$;

CREATE OR REPLACE FUNCTION public._checker_place(p_firm uuid, p_section text, p_f jsonb, p_url text, p_level smallint, p_check integer, p_origin bigint)
 RETURNS TABLE(outcome text, reason text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'bots', 'public'
AS $function$
declare kept uuid; mk bigint; why text; old_text text; new_text text; old_level smallint; old_date text; new_date text;
  new_wins boolean; raw_new text; raw_old text;
begin
  -- Fix 5: do not publish or merge an SEC adviser summary over a legal row.
  if p_section = 'legal' and public._sec_adviser_summary('regulator', coalesce(p_f->>'title', '')) then
    perform public._block_sec_summary(p_firm, 'checker', coalesce(p_f->>'title', ''), null);
    outcome := 'blocked';
    reason := public._sec_summary_reason();
    return next; return;
  end if;

  -- Fix 7: Headquarters is not a profile card. Route it, or block it.
  if p_section = 'overview' and public._hq_label(p_f->>'label') then
    why := public._place_hq_item(p_firm, p_f, p_url, coalesce(p_f->>'date', p_f->>'as_of'));
    reason := 'One home per field (fix 7): Headquarters is stored only in firms.hq_city, firms.hq_region, and firms.hq_country, not as a firm_profile_facts row. Row not stored; '
      || coalesce(why, 'routed to firms.hq_city/hq_region/hq_country') || '.';
    insert into public.money_home_blocked(table_name, op, firm_id, label, value, routed_to, reason)
    values ('firm_profile_facts', 'checker', p_firm, left(coalesce(p_f->>'label', 'Headquarters'), 200),
            left(coalesce(p_f->>'city', p_f->>'value', ''), 500),
            case when why is null then 'firms.hq_city' else null end, reason);
    outcome := 'blocked';
    return next; return;
  end if;
  new_text := public._checker_item_text(p_section, p_f);
  new_date := nullif(p_f->>'date', '');
  raw_new := coalesce(p_f->>'headline', p_f->>'event', p_f->>'role', p_f->>'value', p_f->>'name', p_f->>'title', p_f->>'quote', '');
  if p_section = 'press' then
    select p.id, public._norm_txt(p.headline), p.published_label, p.headline
      into kept, old_text, old_date, raw_old
      from press_items p join press_item_firms pf on pf.press_item_id = p.id
     where pf.firm_id = p_firm and public._checker_url_key(p.url) = public._checker_url_key(p_url)
     order by coalesce(pf.hidden, false), p.id limit 1;
  elsif p_section = 'people' then
    select r.id, public._norm_txt(r.role), null::text, r.role into kept, old_text, old_date, raw_old
      from firm_people_roles r
     where r.firm_id = p_firm and r.kind = coalesce(p_f->>'kind', 'officer')
       and r.stable_key = public._person_key(p_f->>'name')
     order by coalesce(r.hidden, false), r.id limit 1;
  elsif p_section = 'overview' then
    select f.id, public._norm_txt(f.value), null::text, f.value into kept, old_text, old_date, raw_old
      from firm_profile_facts f
     where f.firm_id = p_firm and f.section = 'overview'
       and public._norm_txt(coalesce(f.label, f.hero_label)) = public._norm_txt(p_f->>'label')
     order by coalesce(f.hidden, false), f.id limit 1;
  elsif p_section = 'legal' then
    select i.id, public._norm_txt(i.title), i.year_label, i.title into kept, old_text, old_date, raw_old
      from firm_legal_items i
     where i.firm_id = p_firm and i.stable_key = public._legal_key(p_f->>'title')
     order by coalesce(i.hidden, false), i.id limit 1;
  elsif p_section = 'timeline' then
    select t.id, public._norm_txt(t.body), t.date_label, t.body into kept, old_text, old_date, raw_old
      from timeline_events t
     where t.firm_id = p_firm and (
       public._checker_url_key(t.source_url) = public._checker_url_key(p_url)
       or t.stable_key = public._timeline_key(p_f->>'date', p_f->>'event'))
     order by coalesce(t.hidden, false), t.id limit 1;
  elsif p_section = 'founders' then
    select r.id, public._norm_txt(r.body), null::text, r.body into kept, old_text, old_date, raw_old
      from reviews r
     where r.firm_id = p_firm and p_url = any(coalesce(r.source_urls, '{}'))
     order by r.id limit 1;
  elsif p_section in ('funds', 'lps') then
    select f.id, public._norm_txt(f.value), null::text, f.value into kept, old_text, old_date, raw_old
      from firm_profile_facts f
     where f.firm_id = p_firm and f.section = p_section
       and (public._norm_txt(coalesce(f.label, f.hero_label, f.value)) = public._norm_txt(coalesce(p_f->>'name', p_f->>'label'))
            or (p_section = 'funds' and f.stable_key = public._fund_key(coalesce(p_f->>'name', ''))))
     order by coalesce(f.hidden, false), f.id limit 1;
  end if;
  select m.source_level into old_level from checker_marks m
   where m.firm_id = p_firm and m.kind = p_section and (m.url = p_url or m.item_key = p_section || '|' || coalesce(nullif(p_url, ''), left(p_f::text, 200)))
   order by m.checked_on desc limit 1;
  if kept is null then
    mk := public._money_home_mark();
    perform public._checker_write(p_firm, p_section, p_f, p_url, p_level, p_check);
    why := public._money_home_since(p_firm, mk);  -- fix 3b: confirm the row was saved
    if why is not null then outcome := 'blocked'; reason := why; return next; return; end if;
    outcome := 'published'; reason := null; return next; return;
  end if;
  if old_text is not distinct from new_text then
    perform public._checker_keep_one_exact(p_firm);
    outcome := 'skipped'; reason := 'exact duplicate, kept one'; return next; return;
  end if;
  old_level := coalesce(old_level, 4);
  if p_level < old_level then new_wins := true;
  elsif p_level > old_level then new_wins := false;
  elsif new_date is not null and old_date is not null and new_date > old_date then new_wins := true;
  elsif new_date is not null and old_date is not null and new_date < old_date then new_wins := false;
  elsif length(raw_new) > length(coalesce(raw_old, '')) then new_wins := true;
  elsif length(raw_new) < length(coalesce(raw_old, '')) then new_wins := false;
  else
    perform public._checker_note(p_firm, p_section, p_origin, raw_new, raw_old, 'undecided: same level, date, and length');
    outcome := 'note'; reason := 'undecided, kept the row already on the page'; return next; return;
  end if;
  if new_wins then
    if p_section = 'press' then
      update press_items set headline = left(coalesce(p_f->>'headline', ''), 400), snippet = left(p_f->>'snippet', 600),
             published_label = coalesce(new_date, published_label) where id = kept;
    elsif p_section = 'people' then
      update firm_people_roles set role = left(coalesce(p_f->>'role', ''), 300) where id = kept;
    elsif p_section = 'overview' then
      update firm_profile_facts set value = left(coalesce(p_f->>'value', ''), 400) where id = kept;
    elsif p_section = 'legal' then
      update firm_legal_items set title = left(coalesce(p_f->>'title', ''), 300) where id = kept;
    elsif p_section = 'timeline' then
      update timeline_events set body = left(coalesce(p_f->>'event', ''), 300), date_label = coalesce(new_date, date_label) where id = kept;
    elsif p_section = 'founders' then
      update reviews set body = left(coalesce(p_f->>'quote', ''), 2000) where id = kept;
    elsif p_section in ('funds', 'lps') then
      update firm_profile_facts set value = left(coalesce(p_f->>'name', p_f->>'value', ''), 400) where id = kept;
    end if;
    perform public._checker_stamp(p_section, p_firm, kept, p_level);
    perform public._checker_note(p_firm, p_section, p_origin, raw_old, raw_new, 'merged: new value won, old value kept as a note');
    insert into checker_marks(firm_id, kind, item_key, checked_by, source_level, url)
    values (p_firm, p_section, p_section || '|' || coalesce(nullif(p_url, ''), left(p_f::text, 200)), 'Checker', p_level, p_url)
    on conflict (firm_id, kind, item_key) do update set source_level = least(checker_marks.source_level, excluded.source_level), checked_on = now();
    outcome := 'merged'; reason := 'new value won'; return next; return;
  end if;
  perform public._checker_note(p_firm, p_section, p_origin, raw_new, raw_old, 'merged: page value won, new value kept as a note');
  outcome := 'note'; reason := 'page value won'; return next;
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
    -- 5e) fix 5: the IAPD adviser summary is not a regulator action
    if coalesce(rec->>'field_path', '') = 'regulatoryActions'
       and public._sec_adviser_summary('regulator', coalesce(rec->'value'->>'title', rec->'value'->>'summary', rec->'value'->>'caption', it.f->>'title', '')) then
      r := r || public._sec_summary_reason();
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
    -- 5f) fix 7: Headquarters has one home. A bad record is refused here. A valid one is routed when it is published.
    if coalesce(rec->>'field_path', '') in ('hq', 'headquarters')
       or public._hq_label(it.f->>'label')
       or public._hq_label(rec->'value'->>'label') then
      if public._hq_entry_problem(dom, rec, it.f, it.url) is not null then
        r := r || public._hq_entry_problem(dom, rec, it.f, it.url);
      end if;
    end if;
  end loop;

  -- 6) A9 list limits: never rejected; extra items archived by _entry_fix_payload.

  return (select coalesce(array_agg(x order by o), '{}') from (select x, min(o) o from unnest(r) with ordinality u(x, o) group by x) s);
end $function$;

create or replace function public._lab_live_pill(p_firm uuid, p_n int)
returns table(state text, count_label text, why text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare
  looked boolean; sub bigint; fin int := 0; sav int := 0; items int := 0; hot int := 0;
  iapd text; v_state text; v_count text; v_why text; stored_st text; stored_cnt text;
begin
  select (r.searched_at is not null or r.checked_on is not null), r.source_submission, r.state, r.count_label
    into looked, sub, stored_st, stored_cnt
  from firm_check_rows r where r.firm_id = p_firm and r.n = p_n;
  if not found then
    return query select 'nc'::text, null::text, 'no check row'::text;
    return;
  end if;

  if sub is not null then
    select count(*)::int into fin from check_findings(sub) c where c.k = p_n;
  end if;
  select count(*)::int into sav from check_saved_items(p_firm, p_n);
  items := case when fin > 0 then fin else sav end;

    if p_n = 8 then
    if public._check8_outside_us(p_firm) then
      v_state := 'nc';
      v_count := 'SEC register doesn''t apply: firm is based outside the US';
      v_why := v_count;
    else
    select v.value->>'value' into iapd
    from vc_source_facts v
    where v.firm_id = p_firm and v.superseded_by is null
      and v.value->>'field' = 'registration_status'
      and coalesce(v.source_url, '') ~* 'adviserinfo\.sec\.gov|sec\.gov'
      and coalesce(v.value->>'value', '') !~* 'separate adviser|relying adviser'
      and coalesce(v.value->>'value', '') ~* 'SEC-registered|Exempt reporting|\mERA\M|Registered, Approved|status Approved'
    order by v.retrieved_at desc nulls last
    limit 1;
    if iapd is null then
      select p.value into iapd
      from firm_profile_facts p
      join fact_sources fs on fs.fact_type = 'firm_profile_facts' and fs.fact_id = p.id
      join sources s on s.id = fs.source_id and s.url ~* 'adviserinfo\.sec\.gov'
      where p.firm_id = p_firm and not p.hidden
        and p.value ~* 'SEC-registered|Exempt Reporting Adviser|Exempt reporting adviser'
      order by p.sort_order
      limit 1;
    end if;
    if iapd is not null then
      v_state := 'clear'; v_count := null; v_why := 'IAPD registration row';
    else
      v_state := 'nc'; v_count := null; v_why := 'no IAPD registration row';
    end if;
    end if;
  elsif items > 0 and p_n = 6 then
    if fin > 0 then
      select count(*)::int into hot from check_findings(sub) c
       where c.k = 6 and coalesce(c.status, '') ~* 'active|open|pending|ongoing'
         and coalesce(c.status, '') !~* '^(dismissed|closed|settled|withdrawn)';
    else
      select count(*)::int into hot from check_saved_items(p_firm, 6) c
       where coalesce(c.status, '') ~* 'active|open|pending|ongoing'
         and coalesce(c.status, '') !~* '^(dismissed|closed|settled|withdrawn)';
    end if;
    if hot > 0 then
      v_state := 'review'; v_why := 'a finding is active, open, or pending';
    else
      v_state := 'wk'; v_why := 'findings are closed cases';
    end if;
    if hot > 0 and hot = items then
      v_count := case when items = 1 then '1 active case' else items::text || ' active cases' end;
    else
      v_count := case when items = 1 then '1 case' else items::text || ' cases' end;
    end if;
  elsif items > 0 and p_n = 4 then
    v_state := 'review';
    if fin > 0 then
      select count(*)::int into hot from check_findings(sub) c
       where c.k = 4 and coalesce(c.status, '') ~* 'open|probe'
         and coalesce(c.status, '') !~* 'settled|closed';
    else
      select count(*)::int into hot from check_saved_items(p_firm, 4) c
       where coalesce(c.status, '') ~* 'open|probe'
         and coalesce(c.status, '') !~* 'settled|closed';
    end if;
    if hot > 0 then
      v_count := case when hot = 1 then '1 open probe' else hot::text || ' open probes' end;
      v_why := 'open regulator findings';
    else
      v_count := case when items = 1 then '1 action' else items::text || ' actions' end;
      v_why := 'regulator findings';
    end if;
  elsif items > 0 and p_n = 10 then
    v_state := 'wk';
    v_count := case when items = 1 then '1 record' else items::text || ' records' end;
    v_why := 'political-tie findings';
  elsif items > 0 and p_n = 9 then
    v_state := 'review';
    v_count := case when items = 1 then '1 finding' else items::text || ' findings' end;
    v_why := 'people-screen findings';
  elsif items > 0 and p_n = 7 then
    v_state := 'clear';
    v_count := case when items = 1 then '1 non-party mention' else items::text || ' non-party mentions' end;
    v_why := 'non-US findings';
  elsif items > 0 then
    v_state := 'review';
    v_count := case when items = 1 then '1 record' else items::text || ' records' end;
    v_why := 'findings on this check';
  elsif looked then
    v_state := case when p_n = 10 then 'nf' else 'clear' end;
    v_count := null;
    v_why := 'searched, no findings';
  else
    v_state := 'nc';
    v_count := null;
    v_why := 'no findings and this check was not searched';
  end if;

  if v_state = stored_st and stored_cnt is not null and v_count is not null
     and (select count(*) from regexp_matches(stored_cnt, '\d+', 'g')) = 1
     and (regexp_match(stored_cnt, '\d+'))[1] = (regexp_match(v_count, '\d+'))[1]
  then
    v_count := stored_cnt;
  end if;

  return query select v_state, v_count, v_why;
end $$;

CREATE OR REPLACE FUNCTION public._lab_live_pill(p_firm uuid, p_n integer, p_fin integer, p_hot integer)
 RETURNS TABLE(state text, count_label text, why text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare
  looked boolean; sub bigint; fin int := 0; sav int := 0; items int := 0; hot int := 0;
  iapd text; v_state text; v_count text; v_why text; stored_st text; stored_cnt text;
begin
  select (r.searched_at is not null or r.checked_on is not null), r.source_submission, r.state, r.count_label
    into looked, sub, stored_st, stored_cnt
  from firm_check_rows r where r.firm_id = p_firm and r.n = p_n;
  if not found then
    return query select 'nc'::text, null::text, 'no check row'::text;
    return;
  end if;
  -- p_fin: findings for (sub, p_n) precomputed by the caller (0 when sub is null). null = compute here.
  if p_fin is not null then fin := p_fin;
  elsif sub is not null then
    select count(*)::int into fin from check_findings(sub) c where c.k = p_n;
  end if;
  select count(*)::int into sav from check_saved_items(p_firm, p_n);
  items := case when fin > 0 then fin else sav end;
    if p_n = 8 then
    if public._check8_outside_us(p_firm) then
      v_state := 'nc';
      v_count := 'SEC register doesn''t apply: firm is based outside the US';
      v_why := v_count;
    else
    select v.value->>'value' into iapd
    from vc_source_facts v
    where v.firm_id = p_firm and v.superseded_by is null
      and v.value->>'field' = 'registration_status'
      and coalesce(v.source_url, '') ~* 'adviserinfo\.sec\.gov|sec\.gov'
      and coalesce(v.value->>'value', '') !~* 'separate adviser|relying adviser'
      and coalesce(v.value->>'value', '') ~* 'SEC-registered|Exempt reporting|\mERA\M|Registered, Approved|status Approved'
    order by v.retrieved_at desc nulls last
    limit 1;
    if iapd is null then
      select p.value into iapd
      from firm_profile_facts p
      join fact_sources fs on fs.fact_type = 'firm_profile_facts' and fs.fact_id = p.id
      join sources s on s.id = fs.source_id and s.url ~* 'adviserinfo\.sec\.gov'
      where p.firm_id = p_firm and not p.hidden
        and p.value ~* 'SEC-registered|Exempt Reporting Adviser|Exempt reporting adviser'
      order by p.sort_order
      limit 1;
    end if;
    if iapd is not null then
      v_state := 'clear'; v_count := null; v_why := 'IAPD registration row';
    else
      v_state := 'nc'; v_count := null; v_why := 'no IAPD registration row';
    end if;
    end if;
  elsif items > 0 and p_n = 6 then
    if fin > 0 and p_hot is not null then
      hot := p_hot;
    elsif fin > 0 then
      select count(*)::int into hot from check_findings(sub) c
       where c.k = 6 and coalesce(c.status, '') ~* 'active|open|pending|ongoing'
         and coalesce(c.status, '') !~* '^(dismissed|closed|settled|withdrawn)';
    else
      select count(*)::int into hot from check_saved_items(p_firm, 6) c
       where coalesce(c.status, '') ~* 'active|open|pending|ongoing'
         and coalesce(c.status, '') !~* '^(dismissed|closed|settled|withdrawn)';
    end if;
    if hot > 0 then v_state := 'review'; v_why := 'a finding is active, open, or pending';
    else v_state := 'wk'; v_why := 'findings are closed cases'; end if;
    if hot > 0 and hot = items then
      v_count := case when items = 1 then '1 active case' else items::text || ' active cases' end;
    else
      v_count := case when items = 1 then '1 case' else items::text || ' cases' end;
    end if;
  elsif items > 0 and p_n = 4 then
    v_state := 'review';
    if fin > 0 and p_hot is not null then
      hot := p_hot;
    elsif fin > 0 then
      select count(*)::int into hot from check_findings(sub) c
       where c.k = 4 and coalesce(c.status, '') ~* 'open|probe' and coalesce(c.status, '') !~* 'settled|closed';
    else
      select count(*)::int into hot from check_saved_items(p_firm, 4) c
       where coalesce(c.status, '') ~* 'open|probe' and coalesce(c.status, '') !~* 'settled|closed';
    end if;
    if hot > 0 then
      v_count := case when hot = 1 then '1 open probe' else hot::text || ' open probes' end;
      v_why := 'open regulator findings';
    else
      v_count := case when items = 1 then '1 action' else items::text || ' actions' end;
      v_why := 'regulator findings';
    end if;
  elsif items > 0 and p_n = 10 then
    v_state := 'wk'; v_count := case when items = 1 then '1 record' else items::text || ' records' end; v_why := 'political-tie findings';
  elsif items > 0 and p_n = 9 then
    v_state := 'review'; v_count := case when items = 1 then '1 finding' else items::text || ' findings' end; v_why := 'people-screen findings';
  elsif items > 0 and p_n = 7 then
    v_state := 'clear'; v_count := case when items = 1 then '1 non-party mention' else items::text || ' non-party mentions' end; v_why := 'non-US findings';
  elsif items > 0 then
    v_state := 'review'; v_count := case when items = 1 then '1 record' else items::text || ' records' end; v_why := 'findings on this check';
  elsif looked then
    v_state := case when p_n = 10 then 'nf' else 'clear' end; v_count := null; v_why := 'searched, no findings';
  else
    v_state := 'nc'; v_count := null; v_why := 'no findings and this check was not searched';
  end if;
  if v_state = stored_st and stored_cnt is not null and v_count is not null
     and (select count(*) from regexp_matches(stored_cnt, '\d+', 'g')) = 1
     and (regexp_match(stored_cnt, '\d+'))[1] = (regexp_match(v_count, '\d+'))[1]
  then v_count := stored_cnt; end if;
  return query select v_state, v_count, v_why;
end $function$;

