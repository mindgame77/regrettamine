-- Tasks F + G (Alex approved, Oct 24): trusted-source allowlist + source tiers + needs_source queue.
-- Raw bot data (research_submissions.payload) is never modified. See docs/SOURCE_TIERS.md.
--
-- F. trusted_source_domains: the allowlist used by research-ingest, the enricher and the bots (served by the ingest
--    'sources' action). A URL whose host is a listed domain or a subdomain of one is tier 'trusted'.
-- G. source_tier(url): 'trusted' | 'other' | null (not a usable URL: missing, not http(s), or a search/chat page).
--    Any 'other' URL is accepted and shown, labelled "other source". Records with no usable source are kept, flagged
--    needs_source (hidden publicly) and queued for the Regretamin Enricher (facts_needing_source); once a source is added
--    (fact_add_source) the fact shows.

create table if not exists public.trusted_source_domains (
  domain text primary key check (domain = lower(domain) and domain !~ '[/:\s]'),
  path_like text,               -- informational: e.g. the gov.uk page family that is meant (gov.uk itself is trusted as a whole)
  label text not null,
  kind text not null check (kind in ('regulator', 'register', 'court', 'sanctions', 'government', 'elections')),
  added_at timestamptz not null default now(),
  note text
);
alter table public.trusted_source_domains enable row level security;
revoke all on public.trusted_source_domains from anon, authenticated;
grant select on public.trusted_source_domains to service_role;

insert into public.trusted_source_domains (domain, path_like, label, kind, note) values
  ('sec.gov', null, 'SEC', 'regulator', 'EDGAR, IAPD, litigation releases'),
  ('adviserinfo.sec.gov', null, 'SEC IAPD', 'regulator', null),
  ('finra.org', null, 'FINRA', 'regulator', 'BrokerCheck'),
  ('courtlistener.com', null, 'CourtListener', 'court', null),
  ('uscourts.gov', null, 'U.S. Courts', 'court', null),
  ('pacer.gov', null, 'PACER', 'court', null),
  ('gleif.org', null, 'GLEIF', 'register', 'LEI register'),
  ('find-and-update.company-information.service.gov.uk', null, 'Companies House', 'register', 'Task F'),
  ('api.company-information.service.gov.uk', null, 'Companies House API', 'register', 'Task F'),
  ('companieshouse.gov.uk', null, 'Companies House', 'register', 'Task F'),
  ('fec.gov', null, 'FEC', 'elections', 'Task F'),
  ('sanctionssearch.ofac.treas.gov', null, 'OFAC Sanctions List Search', 'sanctions', 'Task F'),
  ('ofac.treasury.gov', null, 'OFAC', 'sanctions', 'Task F'),
  ('treasury.gov', null, 'U.S. Treasury', 'sanctions', 'Task F'),
  ('home.treasury.gov', null, 'U.S. Treasury', 'sanctions', 'Task F'),
  ('gov.uk', '/government/publications/the-uk-sanctions-list%, /government/organisations/foreign-commonwealth-development-office%', 'GOV.UK', 'government', 'Task F: UK sanctions list + FCDO pages'),
  ('sanctionslist.fcdo.gov.uk', null, 'UK Sanctions List', 'sanctions', 'Task F'),
  ('fcdo.gov.uk', null, 'FCDO', 'government', 'Task F'),
  ('sanctionsmap.eu', null, 'EU Sanctions Map', 'sanctions', 'Task F'),
  ('un.org', '/securitycouncil/sanctions%, scsanctions.un.org', 'UN Security Council', 'sanctions', 'Task F: UN SC consolidated list'),
  ('scsanctions.un.org', null, 'UN SC Sanctions List', 'sanctions', 'Task F')
on conflict (domain) do nothing;

insert into public.source_label_map (domain, url_like, label) values
  ('find-and-update.company-information.service.gov.uk', null, 'Companies House'),
  ('api.company-information.service.gov.uk', null, 'Companies House'),
  ('companieshouse.gov.uk', null, 'Companies House'),
  ('fec.gov', null, 'FEC'),
  ('sanctionssearch.ofac.treas.gov', null, 'OFAC'),
  ('ofac.treasury.gov', null, 'OFAC'),
  ('sanctionsmap.eu', null, 'EU Sanctions Map'),
  ('scsanctions.un.org', null, 'UN Security Council'),
  ('fcdo.gov.uk', null, 'FCDO'),
  ('sanctionslist.fcdo.gov.uk', null, 'UK Sanctions List')
on conflict do nothing;

-- search/chat result pages are never a source (same list as before)
create or replace function public._src_search_page(u text) returns boolean language sql immutable as $$
  select coalesce(u, '') ~* '(google\.[a-z.]+/search|bing\.com/search|duckduckgo\.com/\?|grok\.com|x\.com/i/grok|chatgpt\.com|perplexity\.ai/search)' $$;

-- 'trusted': allowlisted domain (or subdomain), or an official government / court / military host. 'other': any other web URL.
create or replace function public.source_tier(u text) returns text language sql stable set search_path = public as $$
  with d as (select substring(lower(coalesce(u, '')) from '^https?://(?:www\.)?([^/:?#\s]+)') h)
  select case
    when u is null or d.h is null or d.h !~ '\.' or u ~ '\s' or _src_search_page(u) then null
    when exists (select 1 from trusted_source_domains t where d.h = t.domain or d.h like '%.' || t.domain) then 'trusted'
    when d.h ~ '(\.gov|\.gov\.[a-z]{2}|\.gouv\.[a-z]{2}|\.mil|\.europa\.eu|\.gc\.ca|\.admin\.ch)$' and d.h !~ 'embass' then 'trusted'
    when d.h ~ '(^|\.)courts?\.' or d.h ~ '\.courts?\.[a-z.]+$' then 'trusted'
    else 'other' end
  from d $$;
grant execute on function public.source_tier(text) to service_role;

-- G: every real web URL is accepted now (tagged by tier); only search/chat pages and non-URLs are refused.
create or replace function public._promo_src_ok(u text) returns boolean language sql stable set search_path = public as $$
  select public.source_tier(u) is not null $$;
create or replace function public._enrich_src_ok(u text) returns boolean language sql stable set search_path = public as $$
  select coalesce(u, '') ~* '^https?://[^\s/]+\.[^\s]+$' and public.source_tier(u) is not null $$;

-- Sources the Enricher adds to a bot record that had none (raw payload untouched).
create table if not exists public.fact_source_additions (
  id bigint generated always as identity primary key,
  submission_id bigint not null references public.research_submissions(id) on delete cascade,
  record_id text not null,
  url text not null check (public.source_tier(url) is not null),
  quote text,
  retrieved_at timestamptz not null default now(),
  added_by text,
  created_at timestamptz not null default now(),
  unique (submission_id, record_id, url)
);
alter table public.fact_source_additions enable row level security;
revoke all on public.fact_source_additions from anon, authenticated;
grant select, insert, delete on public.fact_source_additions to service_role;

-- usable sources of one record: the bot's own (valid URLs only) + those the Enricher added
create or replace function public._rec_sources(p_sub bigint, r jsonb) returns jsonb language sql stable set search_path = public as $$
  select coalesce(jsonb_agg(x), '[]') from (
    select x from jsonb_array_elements(case when jsonb_typeof(r->'sources') = 'array' then r->'sources' else '[]' end) x
     where jsonb_typeof(x) = 'object' and source_tier(x->>'url') is not null
    union all
    select jsonb_build_object('url', a.url, 'quote', a.quote, 'retrieved_at', a.retrieved_at, 'added_by', a.added_by)
      from fact_source_additions a where a.submission_id = p_sub and a.record_id = r->>'record_id') s $$;

create or replace function public._rec_tier(p_sub bigint, r jsonb) returns text language sql stable set search_path = public as $$
  select case when bool_or(source_tier(x->>'url') = 'trusted') then 'trusted' when count(*) > 0 then 'other' else 'needs_source' end
    from jsonb_array_elements(public._rec_sources(p_sub, r)) x $$;

-- Enricher queue: records in the latest valid submission per firm that have no usable source yet. Service role only.
create or replace view public.facts_needing_source with (security_invoker = true) as
  with latest as (
    select distinct on (s.registry_id) s.id, s.registry_id, s.received_at, s.payload
      from research_submissions s where s.valid order by s.registry_id, s.received_at desc, s.id desc)
  select l.id submission_id, l.registry_id, f.slug, f.name firm_name, r->>'record_id' record_id,
         r->>'field_path' field_path, r->>'checklist_item' checklist_item, r->'value' value, l.received_at
    from latest l
    cross join lateral jsonb_array_elements(case when jsonb_typeof(l.payload->'records') = 'array' then l.payload->'records' else '[]' end) r
    left join firms f on f.registry_id = l.registry_id and f.deleted_at is null
   where nullif(r->>'record_id', '') is not null and public._rec_tier(l.id, r) = 'needs_source';
revoke all on public.facts_needing_source from anon, authenticated, public;
grant select on public.facts_needing_source to service_role;

-- add a source to a needs_source record; re-promotes the firm so the fact shows
create or replace function public.fact_add_source(p_sub bigint, p_record text, p_url text, p_quote text default null, p_by text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare t text := source_tier(p_url); f uuid;
begin
  if t is null then return jsonb_build_object('status', 'error', 'error', 'not a usable source URL (http(s) page, not a search/chat page)'); end if;
  if not exists (select 1 from research_submissions s, jsonb_array_elements(coalesce(s.payload->'records', '[]')) r
                  where s.id = p_sub and r->>'record_id' = p_record) then
    return jsonb_build_object('status', 'error', 'error', 'unknown submission/record');
  end if;
  insert into fact_source_additions(submission_id, record_id, url, quote, added_by)
  values (p_sub, p_record, p_url, left(p_quote, 1000), left(p_by, 80)) on conflict do nothing;
  for f in select fm.id from firms fm join research_submissions s on s.id = p_sub
            where fm.deleted_at is null and fm.registry_id = _registry_target(s.registry_id) loop
    begin perform promote_bot_facts(f); exception when others then raise warning 'fact_add_source promote %: %', f, sqlerrm; end;
  end loop;
  return jsonb_build_object('status', 'ok', 'tier', t);
end $$;
revoke all on function public.fact_add_source(bigint, text, text, text, text) from public, anon, authenticated;
grant execute on function public.fact_add_source(bigint, text, text, text, text) to service_role;

-- source chips carry the tier; non-trusted ones are labelled as an other source
create or replace function public._src(p_type text, p_id uuid)
 returns jsonb language sql stable set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
      'label', source_label(coalesce(fs.label, s.publisher), s.url) || case when source_tier(s.url) = 'other' then ' · other source' else '' end,
      'date', fs.date_label, 'url', s.url, 'tier', coalesce(source_tier(s.url), 'other')) order by fs.sort_order), '[]')
  from fact_sources fs join sources s on s.id = fs.source_id where fs.fact_type = p_type and fs.fact_id = p_id
$function$;

-- promotion reads sources through _rec_sources (bot sources + Enricher additions)
create or replace function public.promote_bot_facts(p_firm uuid) returns int
language plpgsql security definer set search_path = public as $$
declare qid text := _firm_queue_id(p_firm); k record; rec record; fid uuid; n int := 0;
  hv text; v text; hl text; src jsonb; sid uuid; i int;
begin
  if qid is null then return 0; end if;
  for k in select * from (values ('hq', 'overview', 'Headquarters', 'HQ', array['HQ'], 0),
                                 ('aum', 'funds', 'Assets under management', 'Assets', array['Assets', 'Regulatory AUM', 'AUM'], 0)) t(fp, sec, lbl, hl, same, so) loop
    -- never compete with a curated (non-promoted) card of the same kind
    continue when exists (select 1 from firm_profile_facts where firm_id = p_firm and hero_label = any(k.same) and origin is null);
    select s.id sub, r.value r into rec from research_submissions s, jsonb_array_elements(coalesce(s.payload->'records', '[]')) r
     where s.registry_id = qid and s.valid and r->>'field_path' = k.fp
       and exists (select 1 from jsonb_array_elements(public._rec_sources(s.id, r)) x where coalesce(x->>'url', '') like 'http%' and public._promo_src_ok(x->>'url'))
     order by s.received_at desc, s.id desc limit 1;
    fid := md5('promoted:' || p_firm || ':' || k.fp)::uuid;
    if rec.sub is null then delete from firm_profile_facts where id = fid and origin like 'promoted from submission %' and origin is not null; delete from fact_sources where fact_type = 'firm_profile_facts' and fact_id = fid and not exists (select 1 from firm_profile_facts where id = fid); continue; end if;
    hl := k.hl;
    if k.fp = 'hq' then
      hv := coalesce(rec.r->'value'->>'city', rec.r->>'value'); v := coalesce(rec.r->'value'->>'address', hv);
    else
      hv := case when jsonb_typeof(rec.r->'value'->'amount_usd') = 'number' then _promo_money(rec.r->'value')
                 when jsonb_typeof(rec.r->'value'->'raum_usd') = 'number' then _promo_money(jsonb_build_object('amount_usd', rec.r->'value'->'raum_usd')) end;
      if jsonb_typeof(rec.r->'value'->'amount_usd') is distinct from 'number' and jsonb_typeof(rec.r->'value'->'raum_usd') = 'number' then hl := 'Regulatory AUM'; end if;  -- press_aum text has no cited URL: hide
      v := hv || coalesce(' · ' || (rec.r->'value'->>'basis'), '');
    end if;
    if nullif(trim(hv), '') is null then delete from firm_profile_facts where id = fid and origin like 'promoted from submission %' and origin is not null; delete from fact_sources where fact_type = 'firm_profile_facts' and fact_id = fid and not exists (select 1 from firm_profile_facts where id = fid); continue; end if;
    insert into firm_profile_facts(id, firm_id, section, label, value, hero_label, hero_value, sort_order, origin)
    values (fid, p_firm, k.sec, k.lbl, left(v, 400), hl, left(hv, 60), k.so, 'promoted from submission ' || rec.sub)
    on conflict (id) do update set value = excluded.value, hero_label = excluded.hero_label, hero_value = excluded.hero_value, origin = excluded.origin
      where firm_profile_facts.origin like 'promoted from submission %';
    delete from fact_sources where fact_type = 'firm_profile_facts' and fact_id = fid;
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
  return n;
end $$;
grant execute on function public.promote_bot_facts(uuid) to service_role;

-- public check items: records without any usable source stay hidden (needs_source) until one is added
create or replace function public.check_findings(p_sub bigint)
returns table (k int, title text, yr text, status text, note text, who text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare p jsonb;
begin
  if p_sub is null then return; end if;
  select s.payload into p from research_submissions s where s.id = p_sub and s.valid;
  if p is null then return; end if;
  return query
  with cov as (
    select c, _ck_n(c->>'checklist_item') cn, c->>'status' st, position(':' in coalesce(c->>'checklist_item', '')) > 0 sub,
           coalesce(substring(lower(split_part(c->>'checklist_item', ':', 1)) from ' x ([a-z]+)'), 'firm') scope
      from jsonb_array_elements(case when jsonb_typeof(p->'coverage') = 'array' then p->'coverage' else '[]' end) c),
  covm as (select * from cov where cn is not null),
  rec as (select r->>'record_id' rid, r from jsonb_array_elements(case when jsonb_typeof(p->'records') = 'array' then p->'records' else '[]' end) r),
  lg as (select q->>'query_id' qid, q from jsonb_array_elements(case when jsonb_typeof(p->'search_log') = 'array' then p->'search_log' else '[]' end) q),
  item_recs as (select covm.c, rec.r from covm
      cross join lateral jsonb_array_elements_text(case when jsonb_typeof(covm.c->'record_ids') = 'array' then covm.c->'record_ids' else '[]' end) x(rid)
      join rec on rec.rid = x.rid),
  lnk as (
    select covm.cn, rec.rid, rec.r from covm
      cross join lateral jsonb_array_elements_text(case when jsonb_typeof(covm.c->'record_ids') = 'array' then covm.c->'record_ids' else '[]' end) x(rid)
      join rec on rec.rid = x.rid
     where covm.st = 'records'
    union
    select _ck_n(r->>'checklist_item'), rid, r from rec where _ck_n(r->>'checklist_item') is not null),
  fnd as (
    select distinct on (k, rid) case when cn = 6 and _ck_non_us(r) then 7 else cn end k, rid, r,
           lower(coalesce(r->'value'->>'severity', '')) sev, lower(coalesce(r->'value'->>'status', '')) rst
      from lnk where cn <> 8 and _ck_finding(r) and public._rec_tier(p_sub, r) <> 'needs_source')
  select fnd.k,
         coalesce(v->>'caption', v->>'regulator', case when v->>'kind' = 'donation' then nullif(concat_ws(' → ', v->>'donor', v->>'recipient'), '') end,
                  v->>'list', v->>'title', v->>'name',
                  case when v ? 'theme' then initcap(replace(split_part(v->>'theme', '.', 2), '_', ' ')) end,
                  v->'subject'->>'name')::text,
         left(coalesce(v->>'filed_at', v->>'date', v->>'event_date', v->>'cycle', v->>'first_reported'), 4)::text,
         nullif(nullif(v->>'status', ''), 'unknown')::text,
         coalesce(v->>'summary', v->>'allegation', v->>'note')::text,
         case when fnd.r->>'checklist_item' ~* ' x partner' and v->>'kind' is distinct from 'donation' then coalesce(v->>'donor', v->'subject'->>'name') end::text
    from fnd cross join lateral (select coalesce(fnd.r->'value', '{}') v) x;
end $$;
revoke all on function public.check_findings(bigint) from public, anon, authenticated;
