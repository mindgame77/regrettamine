-- The Enricher (bot_id toxy-enricher) is the only bot that writes a public firm page.
-- It publishes at ingest. No batch approval. Other bots only fill the bots holding tables.
-- The research queue stays a to-do list and does not create a firm.
-- Linking a visitor request does not create a firm. The link is kept.
-- A researcher upload and a submissions batch do not write the page.
-- Hand tools stay (edit_in_place, record_removed, restore_hidden, merge_firms, rename_firm_slug).
-- Signed-in admins lose direct write policies on firm and page tables. Service-role hand tools still bypass row security.

-- The queue does not create a page.
create or replace function public.research_queue_page_trg() returns trigger
language plpgsql security definer set search_path = bots, public as $$
begin
  return null;
end $$;

-- Researcher uploads do not copy facts or check rows onto a page, even if the old switch is on.
create or replace function public.promote_bot_facts_trg() returns trigger
language plpgsql security definer set search_path = bots, public as $$
begin
  return null;
end $$;

create or replace function public.checks_from_upload_trg() returns trigger
language plpgsql security definer set search_path = bots, public as $$
begin
  return null;
end $$;

-- A researcher report does not count as research for the page, and is not copied onto it.
create or replace function public.ensure_firm_for_registry(p_registry text, p_fill boolean default true) returns uuid
language plpgsql security definer set search_path = bots, public as $$
declare t text := _registry_target(p_registry); q research_queue; fid uuid; created boolean := false; researched boolean;
  dn text; base text; slg text; sfx int := 1; dom text; hq text; linked int := 0;
begin
  select * into q from research_queue where registry_id = t;
  if q.registry_id is null then return null; end if;
  researched := exists (
    select 1 from research_enrichments e
     where e.bot_id = 'toxy-enricher' and e.valid and e.registry_id in (t, p_registry));
  if nullif(q.sec_crd, '') is not null then
    select id into fid from firms where sec_crd = q.sec_crd and deleted_at is null order by published desc limit 1;
  end if;
  if fid is null then select id into fid from firms where registry_id = t and deleted_at is null; end if;
  if fid is not null then
    update firms set registry_id = t where id = fid and registry_id is null and not exists (select 1 from firms o where o.registry_id = t);
    update firms set published = true, indexable = false where id = fid and not published and not coalesce(is_test, false) and data_status = 'real';
  else
    dn := coalesce(firm_display_name(q.name), q.name);
    base := coalesce(_slugify(dn), lower(t)); slg := base;
    while exists (select 1 from firms where slug = slg) loop sfx := sfx + 1; slg := base || '-' || sfx; end loop;
    dom := substring(lower(btrim(coalesce(q.website, ''))) from '^(?:[a-z]+://)?(?:www\.)?([^/:?#\s]+)');
    if dom is null or dom !~ '\.' or dom ~ '(^|\.)(linkedin|x|twitter|instagram|facebook|youtube|crunchbase|medium|github|angel|wellfound|pitchbook)\.(com|co|io)$' then dom := null; end if;
    hq := firm_hq_format(q.hq_city, q.state, q.country);
    insert into firms (slug, name, display_name, legal_name, hq, sec_crd, primary_domain, firm_type, data_status, source_system, external_id,
                       registry_id, published, indexable)
    values (slg, dn, dn, q.name, hq, nullif(q.sec_crd, ''), dom, case when q.firm_type = 'vc' then 'VC' end, 'real', 'research', t,
            t, true, false)
    returning id into fid;
    created := true;
    insert into firm_check_rows (firm_id, n, title, descr, state, count_label)
    select fid, x.n, x.title, x.descr, 'nc', null from (values
      (1, 'Sanctions', 'Government lists of people and companies you can''t do business with.'),
      (2, 'Terrorism financing lists', 'Lists of people and groups linked to funding terrorism.'),
      (3, 'Export and investment restrictions', 'Trade or investment bans, e.g. deals with military-linked firms.'),
      (4, 'Financial regulator actions', 'Fines, bans and charges from financial regulators.'),
      (5, 'Money laundering penalties', 'Anti-money-laundering fines and enforcement.'),
      (6, 'US court records', 'Federal and state cases, civil and criminal.'),
      (7, 'Court records worldwide', 'Cases outside the U.S.'),
      (8, 'Registration check', 'Registered with the regulator as an investment adviser, and active.'),
      (9, 'People behind the fund', 'Partners and owners, each checked against the lists above.'),
      (10, 'Political ties', 'People at the firm who held government or political roles.')) x(n, title, descr)
    on conflict (firm_id, n) do nothing;
  end if;
  insert into firm_aliases (firm_id, alias, source)
  select fid, a.alias, a.source from (values (btrim(q.name), 'queue_name'),
    (btrim((select legal_name from firms where id = fid)), 'sec_legal')) a(alias, source)
  where coalesce(a.alias, '') <> ''
  on conflict do nothing;
  update research_enrichments set firm_id = fid where firm_id is null and registry_id in (t, p_registry) and bot_id = 'toxy-enricher';
  get diagnostics linked = row_count;
  update search_log set firm_id = fid where firm_id is null and registry_id in (t, p_registry) and bot_id = 'toxy-enricher';
  if p_fill or (created and researched) or linked > 0 then
    begin perform promote_enrichment(fid); exception when others then raise warning 'ensure_firm %: enrichment: %', t, sqlerrm; end;
  end if;
  if exists (
    select 1 from publish_checks c
     where c.firm_id = fid and c.origin = 'enrichment' and c.outcome in ('published', 'merged')
       and exists (select 1 from research_enrichments e where e.id = c.origin_id and e.bot_id = 'toxy-enricher')
  ) then
    update firms set indexable = true
     where id = fid and published and not indexable and not coalesce(is_test, false) and data_status = 'real';
  end if;
  return fid;
end $$;

-- Only the Enricher's waiting rows can be published. Other bots stay in the holding table.
create or replace function public._waiting_enrichments(p_firm uuid) returns setof bots.research_enrichments
language sql stable set search_path = bots, public as $$
  select e.* from research_enrichments e
   where e.firm_id = p_firm and e.valid and e.bot_id = 'toxy-enricher'
     and not exists (select 1 from publish_checks c where c.origin = 'enrichment' and c.origin_id = e.id and c.firm_id = e.firm_id
                      and (c.outcome in ('published', 'merged', 'conflict', 'held') or c.batch_id is not null))
   order by e.received_at desc, e.id desc $$;

create or replace function public._enrichment_after_insert() returns trigger
language plpgsql security definer set search_path = bots, public as $$
begin
  if new.valid and new.bot_id = 'toxy-enricher' and new.firm_id is not null then
    perform promote_enrichment(new.firm_id);
  end if;
  if new.valid then
    perform search_log_from_enrichment(new.id);
    perform refresh_feedback_patterns();
  end if;
  return null;
end $$;
revoke all on function public._enrichment_after_insert() from public, anon, authenticated;

create or replace function public._promote_submissions(p_firm uuid) returns jsonb
language plpgsql security definer set search_path = bots, public as $$
begin
  return jsonb_build_object('facts', 0, 'check_rows_changed', 0, 'submission_id', null, 'closed', true,
    'reason', 'researcher submissions do not write the public page');
end $$;
revoke all on function public._promote_submissions(uuid) from public, anon, authenticated;

create or replace function public._publish_firm(p_batch text, p_source text, p_firm uuid) returns jsonb
language plpgsql security definer set search_path = bots, public as $$
declare b0 jsonb; b1 jsonb; r0 int; r1 int; c0 int; c1 int; reasons text[] := '{}'; s record; added int; res jsonb;
  items jsonb; blocked jsonb; a0 bigint := coalesce((select max(id) from section_count_alerts), 0);
begin
  perform set_config('app.publish_batch', p_batch, true);
  select jsonb_object_agg(section, n) into b0 from _section_counts_now(p_firm);
  r0 := _firm_rules_n(p_firm); c0 := _firm_collisions_n(p_firm);
  if p_source = 'enricher' then
    res := promote_enrichment(p_firm);
  else
    res := jsonb_build_object('closed', true, 'facts', 0, 'reason', 'researcher submissions do not write the public page');
    reasons := reasons || 'researcher submissions do not write the public page'::text;
  end if;
  select jsonb_object_agg(section, n) into b1 from _section_counts_now(p_firm);
  r1 := _firm_rules_n(p_firm); c1 := _firm_collisions_n(p_firm);
  for s in select key sec, (b0->>key)::int a, (b1->>key)::int z from jsonb_each(b0) loop
    if s.a > 0 and s.z = 0 then reasons := reasons || format('section %s went missing (%s -> 0)', s.sec, s.a);
    elsif s.z < s.a then reasons := reasons || format('section %s dropped (%s -> %s)', s.sec, s.a, s.z);
    end if;
  end loop;
  if c1 > c0 then reasons := reasons || format('new duplicates / stable_key collisions (%s -> %s)', c0, c1); end if;
  if r1 > r0 then reasons := reasons || format('more data-rule violations (%s -> %s)', r0, r1); end if;
  for s in select a.section sec, a.kind, a.prev_n, a.new_n from section_count_alerts a
            where a.firm_id = p_firm and a.id > a0 loop
    select count(*) into added from publish_checks where batch_id = p_batch and firm_id = p_firm and outcome = 'published' and section = s.sec;
    if s.kind = 'drop' then reasons := reasons || format('alert: %s dropped %s -> %s', s.sec, s.prev_n, s.new_n);
    elsif (b1->>s.sec)::int - (b0->>s.sec)::int <> added then
      reasons := reasons || format('alert not explained: %s jumped %s -> %s but batch added %s', s.sec, (b0->>s.sec), (b1->>s.sec), added);
    end if;
  end loop;
  select coalesce(jsonb_object_agg(outcome, x), '{}') into items from
    (select outcome, jsonb_object_agg(coalesce(section, '-'), c) x from
      (select outcome, section, count(*) c from publish_checks where batch_id = p_batch and firm_id = p_firm group by 1, 2) q group by 1) z;
  select coalesce(jsonb_agg(jsonb_build_object('section', section, 'kind', kind, 'outcome', outcome, 'reason', left(reason, 200))), '[]') into blocked
    from publish_checks where batch_id = p_batch and firm_id = p_firm and outcome in ('held', 'conflict');
  return jsonb_build_object('decision', case when cardinality(reasons) = 0 then 'live' else 'held' end, 'reasons', to_jsonb(reasons),
    'items', items, 'blocked', blocked, 'counts_before', b0, 'counts_after', b1, 'alerts',
    (select count(*) from section_count_alerts a where a.firm_id = p_firm and a.id > a0), 'result', res);
end $$;

-- Link a request to a queue row. Do not create a firm. firm_id stays empty until a page exists.
create or replace function public.firm_request_link(p_request bigint, p_registry text) returns json
language plpgsql security definer set search_path = bots, public as $$
declare fr firm_requests; t text; fid uuid; n int;
begin
  select * into fr from firm_requests where id = p_request for update;
  if fr.id is null then return json_build_object('status', 'error', 'error', 'unknown request'); end if;
  select coalesce(duplicate_of, registry_id) into t from research_queue where registry_id = p_registry;
  if t is null then return json_build_object('status', 'error', 'error', 'unknown registry_id'); end if;
  if fr.status = 'linked' and fr.registry_id = t and fr.firm_id is not null then
    n := _firm_request_enqueue(fr.id);
    return json_build_object('status', 'ok', 'registry_id', t, 'filed', n, 'already_linked', true);
  end if;
  select id into fid from firms where registry_id = t and deleted_at is null order by created_at limit 1;
  update firm_requests set status = 'linked', registry_id = t, firm_id = fid, linked_at = coalesce(fr.linked_at, now()), updated_at = now() where id = fr.id;
  update research_queue set status = 'skipped', last_error = 'firm request linked to ' || t, updated_at = now()
   where registry_id = 'req-' || fr.id and registry_id <> t and lane = 'request' and status = 'queued';
  n := _firm_request_enqueue(fr.id);
  return json_build_object('status', 'ok', 'registry_id', t, 'firm_id', fid, 'filed', n);
end $$;

create or replace function public.research_enrich(p_bot text, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = bots, public as $$
declare fid uuid; reg text := nullif(p_payload->>'registry_id', ''); slg text := nullif(p_payload->>'slug', ''); page text; eid bigint;
  acc int; rej int; nts int; errs jsonb; v boolean; pub jsonb; onpage boolean := false; enricher boolean := p_bot = 'toxy-enricher';
begin
  perform bots.apply_limits();
  if slg is not null then select id into fid from firms where slug = slg and deleted_at is null; end if;
  if fid is null and reg is not null then
    select id into fid from firms where deleted_at is null and not coalesce(is_test, false) and registry_id = _registry_target(reg)
     order by published desc limit 1;
    if fid is null and enricher and exists (select 1 from research_queue where registry_id = reg) then
      fid := ensure_firm_for_registry(reg, false);
    end if;
  end if;
  if fid is null and reg is null then return jsonb_build_object('error', 'unknown firm: send "slug" (page slug) or "registry_id"'); end if;
  if reg is null then reg := _firm_queue_id(fid); end if;
  select slug into page from firms where id = fid and published;
  select count(*) filter (where outcome = 'ok'), count(*) filter (where outcome = 'rejected'), count(*) filter (where outcome = 'note'),
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
    select 'enrichment', eid, p_bot, fid, section, kind, field, item, outcome, reason from checked_items(p_payload) where outcome in ('rejected', 'note');
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
    'rules', 'docs/DATA_RULES.md: one structured item per fact; free text only as {"note": "..."}');
end $$;
revoke all on function public.research_enrich(text, jsonb) from public, anon, authenticated;
grant execute on function public.research_enrich(text, jsonb) to bot_writer;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.research_enrich(text, jsonb) to service_role;
  end if;
end $$;

-- Direct writes from a signed-in admin. Visitor inserts (reviews, ratings, corrections, watches) stay.
do $$
declare p text;
begin
  foreach p in array array[
    'firms_admin_write',
    'funds_admin_write', 'fund_entities_admin_write', 'fund_people_admin_write', 'investments_admin_write',
    'reviews_admin_write', 'review_ratings_admin_write',
    'legal_matter_firms_admin_write', 'legal_matters_admin_write', 'legal_matter_parties_admin_write',
    'legal_groups_admin_write', 'legal_group_items_admin_write',
    'filings_admin_write', 'docket_entries_admin_write',
    'regulatory_records_admin_write', 'sanctions_checks_admin_write',
    'fact_sources_admin_write', 'sources_admin_write', 'takeaways_admin_write',
    'firm_meta_items_admin_write', 'firm_ranks_admin_write', 'portfolio_metrics_admin_write',
    'evidence_cards_admin_write', 'evidence_lines_admin_write',
    'score_results_admin_write', 'score_result_parts_admin_write', 'score_lines_admin_write',
    'score_inputs_admin_write', 'score_versions_admin_write', 'score_sections_admin_write',
    'people_admin_write', 'portfolio_companies_admin_write', 'company_founders_admin_write',
    'press_item_firms_admin_write', 'press_items_admin_write',
    'vc_entity_identifiers_admin_all', 'vc_partner_history_admin_all', 'vc_political_activity_admin_all',
    'vc_firm_claims_admin_all', 'vc_context_notes_admin_all'
  ]
  loop
    execute format('drop policy if exists %I on public.%I', p, regexp_replace(p, '_(admin_write|admin_all)$', ''));
  end loop;
end $$;

-- Hand tools stay callable by the service key, and not by the site.
revoke all on function
  public.edit_in_place(text, uuid, uuid, jsonb, text, text),
  public.record_removed(text, uuid, uuid, text, text, boolean),
  public.restore_hidden(text, uuid, uuid, text),
  public.merge_firms(text, text, text),
  public.rename_firm_slug(text, text, text, text)
  from public, anon, authenticated;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function
      public.edit_in_place(text, uuid, uuid, jsonb, text, text),
      public.record_removed(text, uuid, uuid, text, text, boolean),
      public.restore_hidden(text, uuid, uuid, text),
      public.merge_firms(text, text, text),
      public.rename_firm_slug(text, text, text, text)
      to service_role;
  end if;
end $$;
