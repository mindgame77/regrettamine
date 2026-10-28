-- Turn the 10 checks off. Approved by Alex 2026-10-28 10:42 PT: "turning checks off ... we keep the design, but we don't run them",
-- "yes, delete", and no 3-day backup ("we don't need the three-day backup").
-- Kept on purpose: checker_on_submission + cron checker-door-drain / checker-failure-retention (that is the publish pipeline:
-- checker_publish_submission, not the 10 checks), ondemand_tick + refill/downgrade crons (paid credits), check_balances,
-- check_events, check_requests, sanctions_checks, checker_marks, bots.checker_holding, publish_checks.
-- Rollback (re-enable triggers; data is not restorable): supabase/rollbacks/20261029031000_checks_off.sql

-- 1) Triggers that fill check rows / pills.
drop trigger if exists checks_from_upload on bots.research_submissions;
drop trigger if exists zz_check_request_done on bots.research_submissions;
do $$ declare r record; begin
  for r in select tgrelid::regclass t, tgname from pg_trigger where not tgisinternal and tgname in ('zz_pills_mark', 'zz_pills_flush') loop
    execute format('drop trigger if exists %I on %s', r.tgname, r.t);
  end loop;
end $$;

-- 2) The 10 checks as a static list (design only). Pages show them as not checked ('nc').
create or replace function public._check_placeholders()
 returns json language sql immutable set search_path = public as $$
  select json_agg(json_build_object('n', n, 'title', title, 'descr', descr, 'state', 'nc', 'count', null, 'searched_at', null,
                                    'items', '[]'::json, 'itemized', 0, 'name_only', null) order by n)
    from (values (1, 'Sanctions', 'Government lists of people and companies you can''t do business with.'),
                 (2, 'Terrorism financing lists', 'Lists of people and groups linked to funding terrorism.'),
                 (3, 'Export and investment restrictions', 'Trade or investment bans, e.g. deals with military-linked firms.'),
                 (4, 'Financial regulator actions', 'Fines, bans and charges from financial regulators.'),
                 (5, 'Money laundering penalties', 'Anti-money-laundering fines and enforcement.'),
                 (6, 'US court records', 'Federal and state cases, civil and criminal.'),
                 (7, 'Court records worldwide', 'Cases outside the U.S.'),
                 (8, 'Registration check', 'Registered with the regulator as an investment adviser, and active.'),
                 (9, 'People behind the fund', 'Partners and owners, each checked against the lists above.'),
                 (10, 'Political ties', 'People at the firm who held government or political roles.')) t(n, title, descr) $$;

create or replace function public._firm_checks(p_firm uuid)
 returns json language sql stable security definer set search_path = public as $$ select public._check_placeholders() $$;
create or replace function public._firm_checks_compute(p_firm uuid)
 returns json language sql stable security definer set search_path = public as $$ select public._check_placeholders() $$;
create or replace function public._firm_checks_done(p_firm uuid)
 returns integer language sql stable security definer set search_path = public as $$ select 0 $$;

-- 3) Writers become no-ops (signatures kept so callers do not break).
create or replace function public.apply_checks_for_firm(p_firm uuid)
 returns bigint language sql security definer set search_path = bots, public as $$ select null::bigint $$;
create or replace function public._apply_name_only(p_firm uuid)
 returns void language plpgsql security definer set search_path = bots, public as $$ begin return; end $$;
create or replace function public.refresh_firm_check_pills(p_firm uuid)
 returns void language plpgsql security definer set search_path = public as $$ begin return; end $$;
create or replace function public.fold_legacy_marks()
 returns jsonb language sql security definer set search_path = public as $$ select jsonb_build_object('checks_off', true) $$;
create or replace function public._pills_mark()
 returns trigger language plpgsql security definer set search_path = bots, public as $$ begin return null; end $$;
create or replace function public._pills_flush()
 returns trigger language plpgsql security definer set search_path = public as $$ begin return null; end $$;
create or replace function public.checks_from_upload_trg()
 returns trigger language plpgsql security definer set search_path = bots, public as $$ begin return null; end $$;
create or replace function public.check_request_done_trg()
 returns trigger language plpgsql security definer set search_path = bots, public as $$ begin return null; end $$;
revoke all on function public._check_placeholders() from public, anon, authenticated;

-- 4) New firms no longer get 10 stored nc rows; the locked page uses the static list.
CREATE OR REPLACE FUNCTION public.ensure_firm_for_registry(p_registry text, p_fill boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'bots', 'public'
AS $function$
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
  end if;
  insert into firm_aliases (firm_id, alias, source)
  select fid, a.alias, a.source from (values (btrim(q.name), 'queue_name'),
    (btrim((select legal_name from firms where id = fid)), 'sec_legal')) a(alias, source)
  where coalesce(a.alias, '') <> ''
  on conflict do nothing;
  update research_enrichments set firm_id = fid where firm_id is null and registry_id in (t, p_registry) and bot_id = 'toxy-enricher';
  get diagnostics linked = row_count;
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
end $function$;

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
      'firm', json_build_object('slug', f.slug, 'name', coalesce(f.display_name, f.name), 'sec_name', coalesce(f.legal_name, f.name), 'short_name', f.short_name, 'hq', hq, 'website', web, 'assets', assets),
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
    'firm', json_build_object('slug', f.slug, 'name', coalesce(f.display_name, f.name), 'sec_name', coalesce(f.legal_name, f.name), 'short_name', f.short_name, 'hq', hq, 'website', web, 'assets', assets),
    'hero', hero, 'sections', secs,
    'checks', public._firm_checks(f.id),
    'queue', vq, 'started_at', vs, 'details', u->'details', 'outline', null, 'ondemand', _ondemand_view(f.id, p_anon), 'activity', public._firm_activity(f.id, open));
end $function$;

-- 5) Delete check data (structures kept so the view and readers keep working). No backup copy (owner).
truncate public.firm_check_pills_dirty, public.firm_check_pills, public.firm_check_rows;
drop schema if exists backup_pre_checking_20261023 cascade;
drop schema if exists backup_pre_straight_checks_20261023 cascade;
-- cached pages still hold old check rows
delete from public.firm_page_cache;
