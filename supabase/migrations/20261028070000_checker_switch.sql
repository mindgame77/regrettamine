-- Checker as the only publisher, behind a switch that stays OFF.
-- checker_publish = false: the Enricher publishes at ingest, as it does today.
-- checker_publish = true: on the 10 lab firms only, the Enricher does not publish.
--   The row is copied into research_submissions and stays there. Other firms stay on the Enricher path.
-- Nothing is deleted. Existing news check marks are not rewritten.
-- Failed Checker rows live in bots.checker_holding and are removed after 7 days.
-- That job does not touch research_submissions, research_enrichments, or page tables.
-- Rollback: supabase/rollbacks/20261028070000_checker_switch.sql

insert into bots.ingest_settings(key, value)
values ('checker_publish', 'false')
on conflict (key) do nothing;

create or replace function public._checker_publish_on() returns boolean
language sql stable security definer set search_path = bots, public as $$
  select coalesce((select value from ingest_settings where key = 'checker_publish'), 'false') = 'true';
$$;
revoke all on function public._checker_publish_on() from public, anon, authenticated;

create table if not exists public.checker_marks (
  id bigserial primary key,
  firm_id uuid not null references public.firms(id) on delete cascade,
  kind text not null,
  item_key text not null,
  checked_on timestamptz not null default now(),
  checked_by text not null default 'Checker',
  source_level smallint not null check (source_level between 1 and 4),
  url text,
  unique (firm_id, kind, item_key)
);
alter table public.checker_marks enable row level security;
revoke all on public.checker_marks from public, anon, authenticated;

create table if not exists bots.checker_holding (
  id bigserial primary key,
  firm_id uuid,
  origin text,
  origin_id bigint,
  kind text,
  url text,
  outcome text not null check (outcome in ('failure', 'unconfirmed')),
  reason text,
  item jsonb,
  created_at timestamptz not null default now()
);
alter table bots.checker_holding enable row level security;
revoke all on bots.checker_holding from public, anon, authenticated;

-- 1 register, 2 firm site, 3 elsewhere online, null = not a link.
create or replace function public._source_level(p_url text, p_firm uuid, p_check int default null)
returns smallint
language plpgsql stable security definer set search_path = public as $$
declare h text; dom text; kind text;
begin
  if public.source_tier(p_url) is null then return null; end if;
  h := public._dom(p_url);
  if h is null then return null; end if;
  if h = 'opensanctions.org' or h like '%.opensanctions.org' then
    if p_check in (1, 2, 10) then return 1; end if;
    return null;
  end if;
  select t.kind into kind from trusted_source_domains t
   where h = t.domain or h like '%.' || t.domain
   order by length(t.domain) desc limit 1;
  if kind in ('regulator', 'register', 'court', 'sanctions', 'government', 'elections') then
    return 1;
  end if;
  select nullif(lower(primary_domain), '') into dom from firms where id = p_firm;
  if dom is not null and (h = dom or h like '%.' || dom) then return 2; end if;
  return 3;
end $$;
revoke all on function public._source_level(text, uuid, int) from public, anon, authenticated;

-- Registry id first. Else domain + name + HQ, marked no registry ID.
create or replace function public.checker_match_firm(p_registry text, p_domain text, p_name text, p_hq text)
returns table(firm_id uuid, note text)
language sql stable security definer set search_path = public as $$
  with reg as (
    select id from firms
     where deleted_at is null and p_registry is not null and btrim(p_registry) <> ''
       and (registry_id = p_registry or sec_crd = p_registry)
     order by published desc limit 1
  ), soft as (
    select id from firms
     where deleted_at is null
       and not exists (select 1 from reg)
       and p_domain is not null and lower(coalesce(primary_domain, '')) = lower(p_domain)
       and p_name is not null and lower(name) = lower(p_name)
       and lower(coalesce(hq, '')) = lower(coalesce(p_hq, ''))
     order by published desc limit 1
  )
  select id, null::text from reg
  union all
  select id, 'no registry ID' from soft;
$$;
revoke all on function public.checker_match_firm(text, text, text, text) from public, anon, authenticated;

create or replace function public._checker_check_n(p_section text, p_url text) returns int
language sql immutable as $$
  select case
    when coalesce(p_section, '') ~* 'sanction' or p_url ~* 'ofac|sanctions' then 1
    when p_section ~* 'terror' then 2
    when p_section ~* 'export|itar' then 3
    when p_section ~* 'regulat' then 4
    when p_section ~* 'launder|aml' then 5
    when p_section ~* 'court' and p_section ~* 'world|uk|foreign' then 7
    when p_section ~* 'court|legal|lawsuit' then 6
    when p_section ~* 'regist' then 8
    when p_section ~* 'people' then 9
    when p_section ~* 'politic|pep' then 10
    else null end;
$$;

create or replace function public._checker_exists(p_firm uuid, p_section text, p_f jsonb, p_url text)
returns boolean language sql stable security definer set search_path = public as $$
  select case p_section
    when 'press' then exists (
      select 1 from press_items p join press_item_firms pf on pf.press_item_id = p.id
       where pf.firm_id = p_firm and p.url = p_url)
    when 'timeline' then exists (
      select 1 from timeline_events t
       where t.firm_id = p_firm and (
         (t.date_label = p_f->>'date' and public._norm_txt(t.body) = public._norm_txt(p_f->>'event'))
         or (coalesce(t.source_url, '') <> '' and t.source_url = p_url)))
    when 'people' then exists (
      select 1 from firm_people_roles r
       where r.firm_id = p_firm and r.kind = coalesce(p_f->>'kind', 'officer')
         and r.stable_key = public._person_key(p_f->>'name'))
    when 'legal' then exists (
      select 1 from firm_legal_items i
       where i.firm_id = p_firm and i.stable_key = public._legal_key(p_f->>'title'))
    when 'founders' then exists (
      select 1 from reviews r where r.firm_id = p_firm and p_url = any(coalesce(r.source_urls, '{}')))
    when 'lps' then exists (
      select 1 from firm_profile_facts f
       where f.firm_id = p_firm and f.section = 'lps'
         and public._norm_txt(f.label) = public._norm_txt(p_f->>'name'))
    when 'overview' then exists (
      select 1 from firm_profile_facts f
       where f.firm_id = p_firm and f.section = 'overview'
         and public._norm_txt(coalesce(f.label, f.hero_label)) = public._norm_txt(p_f->>'label'))
    when 'funds' then exists (
      select 1 from firm_profile_facts f
       where f.firm_id = p_firm and f.section = 'funds'
         and (public._norm_txt(split_part(f.value, ' · ', 1)) = public._norm_txt(p_f->>'name')
              or f.stable_key = public._fund_key(coalesce(p_f->>'name', ''))))
    else false end;
$$;

create or replace function public._checker_write(p_firm uuid, p_section text, p_f jsonb, p_url text, p_level smallint, p_check int)
returns uuid
language plpgsql security definer set search_path = public as $$
declare rid uuid := gen_random_uuid(); key text; n int := p_check;
begin
  key := p_section || '|' || coalesce(nullif(p_url, ''), left(p_f::text, 200));
  if p_section = 'press' then
    insert into press_items(id, publisher, domain, url, published_label, headline, snippet, data_status, retrieved_at, source_system)
    values (rid, coalesce(p_f->>'outlet', public.source_label(public._dom(p_url), p_url)), public._dom(p_url), p_url,
            p_f->>'date', left(coalesce(p_f->>'headline', ''), 400), left(p_f->>'snippet', 600), 'real', now(), 'checker');
    insert into press_item_firms(press_item_id, firm_id, sort_order, check_mark)
    values (rid, p_firm, 900, 'checked_correct');
  elsif p_section = 'timeline' then
    insert into timeline_events(id, firm_id, date_label, kind, body, sort_order, source_url, check_mark)
    values (rid, p_firm, p_f->>'date', 'Reported', left(coalesce(p_f->>'event', ''), 300), 900, p_url, 'checked_correct');
  elsif p_section = 'people' then
    insert into firm_people_roles(id, firm_id, kind, person_name, role, sort_order)
    values (rid, p_firm, coalesce(p_f->>'kind', 'officer'), left(p_f->>'name', 120), left(coalesce(p_f->>'role', ''), 300), 900);
  elsif p_section in ('overview', 'funds', 'lps') then
    insert into firm_profile_facts(id, firm_id, section, label, value, sort_order, origin)
    values (rid, p_firm, p_section,
            case p_section when 'overview' then p_f->>'label' when 'lps' then p_f->>'name' else 'Funds' end,
            left(case p_section when 'overview' then p_f->>'value' when 'lps' then p_f->>'name' else coalesce(p_f->>'name', '') end, 400),
            900, 'checker');
  elsif p_section = 'legal' then
    insert into firm_legal_items(id, firm_id, grp, title, year_label, status_label, sort_order)
    values (rid, p_firm, 'context', left(coalesce(p_f->>'title', ''), 300), substring(p_f->>'date' from '^(\d{4})'), p_f->>'status', 900);
  elsif p_section = 'founders' then
    insert into reviews(id, firm_id, body, first_hand, verification_status, moderation_status, anonymous, author_name, source_urls,
                        review_type, is_public, source_system, dedupe_key)
    values (rid, p_firm, left(coalesce(p_f->>'quote', ''), 2000), false, 'unverified', 'approved', false,
            left(p_f->>'who', 200), array[p_url], 'founder', true, 'checker', 'url:' || left(p_url, 400));
  elsif n is not null then
    insert into vc_source_facts(firm_id, fact_type, section, value, source_url, source_label, retrieved_at, data_status, source_system, external_id)
    values (p_firm,
            case when n in (1, 2, 10) then 'sanctions_check' when n in (4, 5) then 'regulatory_record' when n = 8 then 'fund_fact' else 'legal_matter' end,
            'checks',
            jsonb_build_object('field', case n when 1 then 'sanctions' when 2 then 'terrorism_lists' when 3 then 'export_restrictions'
              when 4 then 'regulatory_action' when 5 then 'aml_penalties' when 7 then 'courts_worldwide' when 8 then 'registration_status'
              when 9 then 'people_screen' when 10 then 'pep' else 'legal_matter' end, 'value', left(p_f::text, 500)),
            p_url, 'Checker', now(), 'real', 'checker', 'checker:' || p_firm::text || ':' || n::text || ':' || md5(coalesce(p_url, '') || p_f::text));
    rid := gen_random_uuid();
  else
    return null;
  end if;
  insert into checker_marks(firm_id, kind, item_key, checked_by, source_level, url)
  values (p_firm, coalesce(p_section, 'check'), key, 'Checker', p_level, p_url)
  on conflict (firm_id, kind, item_key) do nothing;
  return rid;
end $$;
revoke all on function public._checker_write(uuid, text, jsonb, text, smallint, int) from public, anon, authenticated;

-- Classify the latest valid enrichment for one lab firm. Writes only when p_write is true.
create or replace function public.checker_publish_firm(p_firm uuid, p_write boolean default false, p_probes jsonb default null)
returns jsonb
language plpgsql security definer set search_path = bots, public as $$
declare e bots.research_enrichments; it record; lvl smallint; n int; url text; outcome text; reason text;
  pub int := 0; held int := 0; fail int := 0; skip int := 0; unconf int := 0;
  hq text; hq_level smallint; dom text; open_ok boolean;
begin
  if not public._lab_firm(p_firm) then
    return jsonb_build_object('error', 'checker is lab firms only');
  end if;
  select * into e from research_enrichments
   where firm_id = p_firm and valid order by id desc limit 1;
  if e.id is null then
    return jsonb_build_object('firm_id', p_firm, 'enrichment_id', null, 'published', 0, 'held', 0, 'failure', 0, 'skipped', 0, 'unconfirmed', 0);
  end if;
  for it in select * from public.checked_items(e.payload) c where c.outcome = 'ok' order by c.n loop
    url := it.url;
    n := public._checker_check_n(it.section, url);
    if n is not null and url ~* 'opensanctions\.org' and n not in (1, 2, 10) then
      lvl := null; outcome := 'failure'; reason := 'OpenSanctions is only a source inside checks 1, 2 and 10';
    else
      lvl := public._source_level(url, p_firm, n);
      if lvl is null then
        outcome := 'failure'; reason := 'link is not real (missing, not http, or a search/chat page)';
      elsif p_probes is not null and (p_probes ? url) and (p_probes->>url) in ('false', 'f') then
        outcome := 'failure'; reason := 'link did not open';
      elsif lvl = 3 then
        outcome := 'unconfirmed'; reason := 'Unconfirmed: elsewhere online, not shown';
      elsif public._checker_exists(p_firm, it.section, it.f, url) then
        outcome := 'skipped'; reason := 'already on the page, not re-checked';
      else
        outcome := 'published'; reason := null;
      end if;
    end if;
    if outcome = 'published' and p_write then
      begin
        perform public._checker_write(p_firm, it.section, it.f, url, lvl, n);
      exception when others then
        outcome := 'failure'; reason := 'write failed: ' || sqlerrm;
      end;
    end if;
    if outcome = 'published' then pub := pub + 1;
    elsif outcome = 'unconfirmed' then unconf := unconf + 1; held := held + 1;
    elsif outcome = 'failure' then fail := fail + 1;
    else skip := skip + 1; end if;
    if p_write and outcome in ('failure', 'unconfirmed') then
      insert into checker_holding(firm_id, origin, origin_id, kind, url, outcome, reason, item)
      values (p_firm, 'enrichment', e.id, it.section, url, case when outcome = 'unconfirmed' then 'unconfirmed' else 'failure' end, reason, it.item);
    end if;
  end loop;
  select f.hq, f.primary_domain into hq, dom from firms f where f.id = p_firm;
  select public._source_level(x.url, p_firm, null) into hq_level
    from (
      select coalesce(i->>'source', i->>'url') url
        from jsonb_array_elements(coalesce(e.payload->'sections'->'Overview', '[]'::jsonb)) i
       where lower(coalesce(i->>'label', '')) in ('hq', 'headquarters')
    ) x
   where public._source_level(x.url, p_firm, null) in (1, 2)
   order by public._source_level(x.url, p_firm, null) limit 1;
  return jsonb_build_object(
    'firm_id', p_firm, 'enrichment_id', e.id, 'switch', public._checker_publish_on(),
    'published', pub, 'unconfirmed', unconf, 'held', held, 'failure', fail, 'skipped', skip,
    'submissions_in_holding', (select count(*) from research_submissions s
       where s.registry_id = (select registry_id from firms where id = p_firm)),
    'header', jsonb_build_object('name', (select coalesce(display_name, name) from firms where id = p_firm),
      'short_name', (select short_name from firms where id = p_firm),
      'website', dom, 'hq', hq, 'hq_source_level', hq_level),
    'match', (select jsonb_build_object('firm_id', m.firm_id, 'note', m.note)
                from public.checker_match_firm((select registry_id from firms where id = p_firm), dom,
                     (select name from firms where id = p_firm), hq) m limit 1));
end $$;
revoke all on function public.checker_publish_firm(uuid, boolean, jsonb) from public, anon, authenticated;

create or replace function public.checker_dry_run(p_slug text, p_probes jsonb default null)
returns jsonb
language plpgsql security definer set search_path = bots, public as $$
declare fid uuid; r jsonb;
begin
  select id into fid from firms where slug = p_slug and deleted_at is null;
  if fid is null then return jsonb_build_object('error', 'unknown firm'); end if;
  if not public._lab_firm(fid) then return jsonb_build_object('error', 'checker is lab firms only', 'slug', p_slug); end if;
  begin
    r := public.checker_publish_firm(fid, true, p_probes);
    raise exception using errcode = 'P0001', message = 'checker-dryrun-rollback';
  exception when others then
    if sqlerrm <> 'checker-dryrun-rollback' then
      r := jsonb_build_object('slug', p_slug, 'error', sqlerrm);
    end if;
  end;
  return coalesce(r, '{}'::jsonb) || jsonb_build_object('slug', p_slug, 'dry_run', true, 'switch', public._checker_publish_on());
end $$;
revoke all on function public.checker_dry_run(text, jsonb) from public, anon, authenticated;

create or replace function public.checker_purge_failures() returns int
language plpgsql security definer set search_path = bots, public as $$
declare n int;
begin
  delete from checker_holding where outcome = 'failure' and created_at < now() - interval '7 days';
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.checker_purge_failures() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'checker-failure-retention') then
      perform cron.unschedule('checker-failure-retention');
    end if;
    perform cron.schedule('checker-failure-retention', '40 8 * * *', 'select public.checker_purge_failures()');
  end if;
end $$;

-- Switch OFF: Enricher still publishes. Switch ON and a lab firm: holding only.
-- The row waits in research_submissions. This trigger does not write a page table.
create or replace function public._enrichment_after_insert() returns trigger
language plpgsql security definer set search_path = bots, public as $$
begin
  if new.valid and new.bot_id = 'toxy-enricher' and new.firm_id is not null then
    if public._checker_publish_on() and public._lab_firm(new.firm_id) then
      perform set_config('app.finder_holding', '1', true);
      begin
        insert into research_submissions(bot_id, registry_id, payload, record_count, valid, errors)
        values (new.bot_id, new.registry_id, new.payload, new.accepted, coalesce(new.valid, false), new.errors);
      exception when others then
        insert into checker_holding(firm_id, origin, origin_id, kind, outcome, reason, item)
        values (new.firm_id, 'enrichment', new.id, 'row', 'failure', sqlerrm, new.payload);
      end;
    else
      perform promote_enrichment(new.firm_id);
    end if;
  end if;
  if new.valid then
    perform search_log_from_enrichment(new.id);
    perform refresh_feedback_patterns();
  end if;
  return null;
end $$;
revoke all on function public._enrichment_after_insert() from public, anon, authenticated;

-- Activity Collector must not write investments while the Checker switch is on.
create or replace function public._investments_via_holding() returns trigger
language plpgsql security definer set search_path = bots, public as $$
begin
  if tg_op = 'INSERT' and coalesce(new.source_system, '') like 'activity_collector%'
     and public._checker_publish_on() and public._lab_firm(new.firm_id) then
    begin
      insert into research_submissions(bot_id, registry_id, payload, record_count, valid, errors)
      select 'activity-collector', f.registry_id,
             jsonb_build_object('kind', 'deal', 'company_id', new.company_id, 'round', new.round_name, 'amount', new.amount),
             1, false, jsonb_build_array('held for the Checker')
        from firms f where f.id = new.firm_id and f.registry_id is not null;
    exception when others then
      insert into checker_holding(firm_id, origin, kind, outcome, reason, item)
      values (new.firm_id, 'activity-collector', 'deal', 'failure', sqlerrm,
              jsonb_build_object('round', new.round_name, 'amount', new.amount));
    end;
    return null;
  end if;
  return new;
end $$;
drop trigger if exists investments_via_holding on public.investments;
create trigger investments_via_holding before insert on public.investments
  for each row execute function public._investments_via_holding();

-- Visitor reviews stay on the page while the switch is off. When it is on, they wait in holding.
create or replace function public._reviews_via_holding() returns trigger
language plpgsql security definer set search_path = bots, public as $$
begin
  if tg_op = 'INSERT' and coalesce(new.source_system, '') = 'visitor'
     and public._checker_publish_on() and public._lab_firm(new.firm_id) then
    begin
      insert into research_submissions(bot_id, registry_id, payload, record_count, valid, errors)
      select 'visitor', f.registry_id, jsonb_build_object('kind', 'review', 'body', new.body),
             1, false, jsonb_build_array('held for the Checker')
        from firms f where f.id = new.firm_id and f.registry_id is not null;
    exception when others then
      insert into checker_holding(firm_id, origin, kind, outcome, reason, item)
      values (new.firm_id, 'visitor', 'review', 'failure', sqlerrm, jsonb_build_object('body', left(coalesce(new.body, ''), 500)));
    end;
    return null;
  end if;
  return new;
end $$;
drop trigger if exists reviews_via_holding on public.reviews;
create trigger reviews_via_holding before insert on public.reviews
  for each row execute function public._reviews_via_holding();

create or replace function public.research_enrich(p_bot text, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = bots, public as $$
declare fid uuid; reg text := nullif(p_payload->>'registry_id', ''); slg text := nullif(p_payload->>'slug', ''); page text; eid bigint;
  acc int; rej int; nts int; errs jsonb; v boolean; pub jsonb; onpage boolean := false; enricher boolean := p_bot = 'toxy-enricher';
  lab boolean; matched uuid; note text; dom text; nm text; hq text;
begin
  perform bots.apply_limits();
  if slg is not null then select id into fid from firms where slug = slg and deleted_at is null; end if;
  if fid is null and reg is not null then
    select id into fid from firms where deleted_at is null and not coalesce(is_test, false) and registry_id = _registry_target(reg)
     order by published desc limit 1;
    if fid is null and enricher and exists (select 1 from research_queue where registry_id = reg) then
      if public._checker_publish_on() then
        select q.name, q.hq_city, substring(lower(btrim(coalesce(q.website, ''))) from '^(?:[a-z]+://)?(?:www\.)?([^/:?#\s]+)')
          into nm, hq, dom from research_queue q where q.registry_id = reg;
        select m.firm_id, m.note into matched, note from public.checker_match_firm(reg, dom, nm, hq) m limit 1;
        if matched is not null then
          fid := matched;
        else
          fid := ensure_firm_for_registry(reg, false);
        end if;
      else
        fid := ensure_firm_for_registry(reg, false);
      end if;
    end if;
  end if;
  if fid is null and reg is null then return jsonb_build_object('error', 'unknown firm: send "slug" (page slug) or "registry_id"'); end if;
  if reg is null then reg := _firm_queue_id(fid); end if;
  lab := public._lab_firm(fid);
  select slug into page from firms where id = fid and published;
  select count(*) filter (where outcome = 'ok'), count(*) filter (where outcome = 'rejected'),
    count(*) filter (where outcome = 'note' and (kind is distinct from 'note' or lab)),
    coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'section', section, 'field', field, 'item', left(item::text, 160), 'url', url, 'reason', reason))
      filter (where outcome = 'rejected'), '[]')
    into acc, rej, nts, errs from checked_items(p_payload);
  if (select coalesce(max(id), 0) + 1 from research_enrichments) < _rules_cutoff() then
    select count(*) filter (where ok), count(*) filter (where not ok),
      coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'section', section, 'field', field, 'item', left(txt, 160), 'url', url, 'reason', reason)) filter (where not ok), '[]')
      into acc, rej, errs from enrichment_items(p_payload);
    nts := 0;
  end if;
  v := acc > 0;
  insert into research_enrichments(bot_id, registry_id, slug, firm_id, payload, valid, errors, accepted, rejected)
  values (p_bot, reg, coalesce(slg, (select slug from firms where id = fid)), fid, p_payload, v, errs, acc, rej) returning id into eid;
  if enricher and eid >= _rules_cutoff() then
    insert into publish_checks(origin, origin_id, bot_id, firm_id, section, kind, field, item, outcome, reason)
    select 'enrichment', eid, p_bot, fid, section, kind, field, item, outcome, reason
      from checked_items(p_payload)
     where outcome in ('rejected', 'note')
       and (kind is distinct from 'note' or lab);
  end if;
  onpage := enricher and exists (
    select 1 from publish_checks
     where origin = 'enrichment' and origin_id = eid and outcome in ('published', 'merged'));
  if onpage and fid is not null then
    update firms set indexable = true
     where id = fid and published and deleted_at is null and not coalesce(is_test, false) and data_status = 'real' and not indexable;
    select slug into page from firms where id = fid and published;
  end if;
  if enricher and fid is not null and reg is not null then
    update firm_requests set firm_id = fid, updated_at = now()
     where status = 'linked' and firm_id is null and registry_id in (reg, _registry_target(reg));
    perform _firm_request_enqueue(r.id) from firm_requests r
     where r.firm_id = fid and r.status = 'linked' and r.registry_id in (reg, _registry_target(reg));
  end if;
  select coalesce(jsonb_object_agg(outcome, c), '{}') into pub from (select outcome, count(*) c from publish_checks where origin = 'enrichment' and origin_id = eid group by 1) x;
  return jsonb_build_object('enrichment_id', eid, 'firm', coalesce(page, slg), 'registry_id', reg, 'on_page', onpage, 'valid', v,
    'accepted_items', acc, 'rejected_items', rej, 'notes_kept', nts, 'rejected', errs, 'outcomes', pub,
    'conflicts', coalesce((select jsonb_agg(jsonb_build_object('section', section, 'item', left(item::text, 160), 'reason', reason))
                             from publish_checks where origin = 'enrichment' and origin_id = eid and outcome = 'conflict'), '[]'),
    'rules', 'docs/PAGE_DATA_GUIDE.md');
end $$;
revoke all on function public.research_enrich(text, jsonb) from public, anon, authenticated;
grant execute on function public.research_enrich(text, jsonb) to bot_writer;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.research_enrich(text, jsonb) to service_role;
  end if;
end $$;
