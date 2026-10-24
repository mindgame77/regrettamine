-- Sprint step 3: a 'Not checked yet' page for every research_queue entry with no research yet (same /vc/<slug>/ template).
-- firms.indexable = false marks those pages: published (the page renders and site search finds it, ranked below checked firms)
-- but noindex,follow (firm_meta.indexable -> edge head), left out of the sitemap and of the legacy list/bundle RPCs.
-- ensure_firm_for_registry flips indexable to true when a valid report arrives, so the page upgrades in place (same slug).
-- unlock_firm never spends a credit on an unchecked page (status 'unchecked'); the page routes to the request-a-check form.
-- Flagged duplicates (research_queue.duplicate_of) and skipped entries get no page. Exact lookups only (registry_id / CRD / slug).
-- Backup: /workspace/backups/pre-unchecked-pages-2026-10-24/

alter table public.firms add column if not exists indexable boolean not null default true;
comment on column public.firms.indexable is 'false = ''Not checked yet'' page (no research yet): published, noindex, not in sitemap, ranked below checked firms in suggestions.';

CREATE OR REPLACE FUNCTION public.ensure_firm_for_registry(p_registry text, p_fill boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t text := _registry_target(p_registry); q research_queue; fid uuid; created boolean := false; researched boolean;
  dn text; base text; slg text; sfx int := 1; dom text; hq text; linked int := 0;
begin
  select * into q from research_queue where registry_id = t;
  if q.registry_id is null then return null; end if;
  researched := exists (select 1 from research_submissions s where s.registry_id in (t, p_registry) and s.valid);
  if nullif(q.sec_crd, '') is not null then
    select id into fid from firms where sec_crd = q.sec_crd and deleted_at is null order by published desc limit 1;
  end if;
  if fid is null then select id into fid from firms where registry_id = t and deleted_at is null; end if;
  if fid is not null then
    update firms set registry_id = t where id = fid and registry_id is null and not exists (select 1 from firms o where o.registry_id = t);
    if researched then
      update firms set published = true, indexable = true where id = fid and not (published and indexable) and not coalesce(is_test, false) and data_status = 'real';
    else
      -- no research yet: a hidden firm row becomes a 'Not checked yet' page (noindex); an already published page is left alone
      update firms set published = true, indexable = false where id = fid and not published and not coalesce(is_test, false) and data_status = 'real';
    end if;
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
            t, true, researched)
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
  -- keep the legal / queue name searchable as an alias (firm_suggest)
  insert into firm_aliases (firm_id, alias, source)
  select fid, a.alias, a.source from (values (btrim(q.name), 'queue_name'),
    (btrim((select legal_name from firms where id = fid)), 'sec_legal')) a(alias, source)
  where coalesce(a.alias, '') <> ''
  on conflict do nothing;
  -- link enrichments / search log rows that arrived before the page existed (rows are not copied, so re-sends never duplicate)
  update research_enrichments set firm_id = fid where firm_id is null and registry_id in (t, p_registry);
  get diagnostics linked = row_count;
  update search_log set firm_id = fid where firm_id is null and registry_id in (t, p_registry);
  if p_fill or (created and researched) then
    begin perform apply_checks_for_firm(fid); exception when others then raise warning 'ensure_firm %: checks: %', t, sqlerrm; end;
    begin perform promote_bot_facts(fid); exception when others then raise warning 'ensure_firm %: bot facts: %', t, sqlerrm; end;
  end if;
  if p_fill or (created and researched) or linked > 0 then
    begin perform promote_enrichment(fid); exception when others then raise warning 'ensure_firm %: enrichment: %', t, sqlerrm; end;
  end if;
  return fid;
end $function$
;

CREATE OR REPLACE FUNCTION public.unlock_firm(p_slug text, p_anon uuid, p_spend boolean DEFAULT true)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b public.check_balances := _balance(p_anon); f uuid; ix boolean; h text := _ip_hash(); ip_cap constant int := 4;
begin
  select id, indexable into f, ix from firms where slug = p_slug and deleted_at is null and published and not coalesce(is_test, false) and data_status = 'real';
  if f is null then return json_build_object('status','not_found'); end if;
  if not exists (select 1 from check_events where balance_id = b.id and firm_id = f and kind like 'spend_%') then
    if not p_spend then return json_build_object('status','locked'); end if;
    -- 'Not checked yet' page (no research yet): never spend a credit; the page sends the visitor to the request-a-check form.
    if not ix then return json_build_object('status','unchecked'); end if;
    if b.free_left > 0 and auth.uid() is null and h is not null
       and (select count(*) from check_events where ip_hash = h and kind = 'spend_free' and created_at > now() - interval '30 days') >= ip_cap then
      return json_build_object('status','need_signup');
    end if;
    if b.free_left > 0 then
      update check_balances set free_left = free_left - 1, updated_at = now() where id = b.id;
      insert into check_events(balance_id, firm_id, kind, amount, ip_hash) values (b.id, f, 'spend_free', -1, case when auth.uid() is null then h end);
    elsif b.paid_left > 0 then
      update check_balances set paid_left = paid_left - 1, updated_at = now() where id = b.id;
      insert into check_events(balance_id, firm_id, kind, amount) values (b.id, f, 'spend_paid', -1);
    elsif auth.uid() is null then return json_build_object('status','need_signup');
    else return json_build_object('status','out');
    end if;
  end if;
  return json_build_object('status','ok','details', public.firm_details(f));
end $function$
;

CREATE OR REPLACE FUNCTION public.firm_page(p_slug text, p_anon uuid, p_spend boolean DEFAULT false)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare f firms; u json; open boolean; secs jsonb := '[]'; s page_sections; it jsonb; hero jsonb; q research_queue; qid text;
begin
  select * into f from firms where slug = p_slug and deleted_at is null and published and not coalesce(is_test, false) and data_status = 'real';
  if f.id is null then return json_build_object('status', 'not_found'); end if;
  u := unlock_firm(p_slug, p_anon, p_spend);
  open := u->>'status' = 'ok';
  if u->>'status' not in ('ok', 'locked') then return u; end if;
  if not open then
    -- Locked (blur A): only what every visitor may see: the firm, the SEC hero facts, the 10 check names and the progress count.
    -- No section list, counts, teasers, outline, states, counts or dates of any check; firm_details only on an unlocked page.
    select coalesce(jsonb_agg(jsonb_build_object('label', hero_label, 'value', hero_value, 'anchor', section,
        'src', _src('firm_profile_facts', id)) order by section desc, sort_order), '[]') into hero
      from firm_profile_facts where firm_id = f.id and hero_label is not null and exists (select 1 from fact_sources where fact_type = 'firm_profile_facts' and fact_id = firm_profile_facts.id);
    qid := _firm_queue_id(f.id);
    if qid is not null then select * into q from research_queue where registry_id = qid; end if;
    if not f.indexable and jsonb_array_length(hero) = 0 then
      -- 'Not checked yet' page: registration facts from the research queue row (no source chips: nothing checked yet)
      select coalesce(jsonb_agg(jsonb_build_object('label', l, 'value', v, 'anchor', 'overview', 'src', '[]'::jsonb) order by o), '[]') into hero
        from (values (1, 'HQ', f.hq), (2, 'SEC CRD', nullif(q.sec_crd, '')), (3, 'LEI', nullif(q.lei, ''))) x(o, l, v) where v is not null;
    end if;
    return json_build_object('status', 'ok', 'open', false, 'locked', u->>'status', 'unchecked', not f.indexable,
      'firm', json_build_object('slug', f.slug, 'name', coalesce(f.display_name, f.name), 'sec_name', coalesce(f.legal_name, f.name), 'short_name', f.short_name, 'hq', f.hq),
      'hero', hero, 'sections', '[]'::json, 'done', _firm_checks_done(f.id),
      'checks', (select json_agg(json_build_object('n', n, 'title', title, 'descr', descr, 'state', null, 'count', null, 'searched_at', null,
          'items', null, 'itemized', null) order by n) from firm_check_rows where firm_id = f.id),
      'queue', q.status, 'started_at', case when q.status = 'claimed' then q.claimed_at end, 'details', null, 'outline', null);
  end if;
  for s in select * from page_sections where enabled order by sort_order loop
    it := _sec_items(s.key, f.id);
    continue when jsonb_array_length(it) = 0;
    secs := secs || jsonb_build_object('key', s.key, 'title', s.title, 'subtitle', s.subtitle, 'renderer', s.renderer,
      'count', jsonb_array_length(it), 'unit', case when jsonb_array_length(it) = 1 then s.unit_one else s.unit_many end,
      'teaser', it->0->>'head', 'items', it);
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('label', hero_label, 'value', hero_value, 'anchor', section,
      'src', _src('firm_profile_facts', id)) order by section desc, sort_order), '[]') into hero
    from firm_profile_facts where firm_id = f.id and hero_label is not null and exists (select 1 from fact_sources where fact_type = 'firm_profile_facts' and fact_id = firm_profile_facts.id);
  qid := _firm_queue_id(f.id);
  if qid is not null then select * into q from research_queue where registry_id = qid; end if;
  return json_build_object('status', 'ok', 'open', true, 'unchecked', false, 'done', _firm_checks_done(f.id),
    'firm', json_build_object('slug', f.slug, 'name', coalesce(f.display_name, f.name), 'sec_name', coalesce(f.legal_name, f.name), 'short_name', f.short_name, 'hq', f.hq),
    'hero', hero, 'sections', secs,
    'checks', (select json_agg(json_build_object('n', n, 'title', title, 'descr', descr, 'state', state, 'count', count_label, 'searched_at', searched_at,
        'items', (select coalesce(json_agg(json_build_object('title', i.title, 'year', i.yr, 'status', i.status, 'note', i.note, 'who', i.who) order by i.yr desc nulls last, i.title), '[]') from check_findings(source_submission) i where i.k = n),
        'itemized', (select count(*) from check_findings(source_submission) i where i.k = n)) order by n) from firm_check_rows where firm_id = f.id),
    'queue', q.status, 'started_at', case when q.status = 'claimed' then q.claimed_at end,
    'details', u->'details', 'outline', null);
end $function$
;

CREATE OR REPLACE FUNCTION public.firm_sitemap(p_page integer DEFAULT 1, p_size integer DEFAULT 10000)
 RETURNS TABLE(slug text, updated_at timestamp with time zone, total bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with pub as (
    select f.slug, f.updated_at from public.firms f
    where f.published and f.indexable and not coalesce(f.is_test, false) and f.deleted_at is null and f.data_status = 'real'
  )
  select p.slug, p.updated_at, (select count(*) from pub) from pub p
  order by p.slug
  offset greatest(coalesce(p_page, 1) - 1, 0) * least(greatest(coalesce(p_size, 10000), 1), 10000)
  limit least(greatest(coalesce(p_size, 10000), 1), 10000)
$function$
;

CREATE OR REPLACE FUNCTION public.firm_suggest(q text)
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with t as (select lower(trim(q)) t), pub as (
    select f.* from firms f where f.published and not coalesce(f.is_test, false) and f.data_status = 'real' and f.deleted_at is null
  ), m as (
    select f.slug, coalesce(f.display_name, f.name) as name, f.short_name, f.hq, f.indexable,
      case when lower(coalesce(f.display_name, f.name)) like t || '%' or lower(coalesce(f.short_name, '')) like t || '%' or f.slug like t || '%' then 0
           when lower(coalesce(f.display_name, f.name)) ~ ('\m' || regexp_replace(t, '([^a-z0-9 ])', '\\\1', 'g')) then 1 else 2 end r
    from pub f, t
    where length(t) > 0
      and (lower(coalesce(f.display_name, f.name)) like '%' || t || '%' or lower(coalesce(f.short_name, '')) like '%' || t || '%' or f.slug like '%' || t || '%')
    union all
    select f.slug, coalesce(f.display_name, f.name), f.short_name, f.hq, f.indexable,
      case when lower(a.alias) like t || '%' then 0 when lower(a.alias) ~ ('\m' || regexp_replace(t, '([^a-z0-9 ])', '\\\1', 'g')) then 1 else 2 end
    from firm_aliases a join pub f on f.id = a.firm_id, t
    where length(t) > 0 and lower(a.alias) like '%' || t || '%'
  ), d as (select slug, name, short_name, hq, indexable, min(r) r from m group by slug, name, short_name, hq, indexable)
  select coalesce(json_agg(json_build_object('slug', slug, 'name', name, 'short_name', short_name, 'hq', hq) order by not indexable, r, name), '[]')
  from (select * from d order by not indexable, r, name limit 8) x
$function$
;

drop function if exists public.firm_meta(text);
CREATE OR REPLACE FUNCTION public.firm_meta(p_slug text)
 RETURNS TABLE(slug text, name text, short_name text, hq text, firm_type text, legal_name text, primary_domain text, founded_year integer, updated_at timestamp with time zone, indexable boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select f.slug, coalesce(f.display_name, f.name), f.short_name, f.hq, f.firm_type, f.legal_name, f.primary_domain, f.founded_year::int, f.updated_at, f.indexable
  from public.firms f
  where f.slug = lower(p_slug) and f.published and not coalesce(f.is_test, false)
    and f.deleted_at is null and f.data_status = 'real'
  limit 1
$function$
;
revoke all on function public.firm_meta(text) from public;
grant execute on function public.firm_meta(text) to anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.next_firms_to_enrich(p_limit integer DEFAULT 20)
 RETURNS TABLE(slug text, registry_id text, name text, published boolean, score numeric, done bigint, total bigint, missing text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select slug, registry_id, name, published, score, done, total,
    array_agg(item order by item) filter (where status not in ('filled', 'searched_none'))
  from firm_section_status where slug not in (select slug from firms where not indexable) group by 1, 2, 3, 4, 5, 6, 7
  order by published desc, score asc, name limit greatest(1, least(coalesce(p_limit, 20), 500)) $function$
;

CREATE OR REPLACE FUNCTION public.landing_funds()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tier text := public.access_tier();
  v_limit integer := public.tier_list_limit(v_tier);
  v_total integer;
  v_funds jsonb;
begin
  select count(*) into v_total
  from public.firms
  where published and indexable and not is_test;

  select coalesce(jsonb_agg(public.firm_list_row(f) order by ranked.rank), '[]'::jsonb)
  into v_funds
  from public.firms f
  join (
    select id, row_number() over (order by coalesce(list_score_exact, list_score) desc nulls last, name) as rank
    from public.firms
    where published and indexable and not is_test
  ) ranked on ranked.id = f.id
  where v_limit is null or ranked.rank <= v_limit;

  return jsonb_build_object(
    'tier', v_tier,
    'limit', v_limit,
    'total', v_total,
    'funds', v_funds
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.search_funds(q text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  cleaned text;
  v_tier text := public.access_tier();
  v_limit integer := public.tier_list_limit(v_tier);
  v_hits jsonb;
begin
  cleaned := left(regexp_replace(btrim(coalesce(q, '')), '[%_\\]', '', 'g'), 80);
  if cleaned = '' then
    return '[]'::jsonb;
  end if;

  select coalesce(jsonb_agg(
    case
      when v_limit is null or ranked.rank <= v_limit then
        public.firm_list_row(f) || jsonb_build_object(
          'slug', f.slug,
          'rank', ranked.rank,
          'inTier', true
        )
      else jsonb_build_object(
        'id', f.slug,
        'name', f.name,
        'slug', f.slug,
        'rank', ranked.rank,
        'inTier', false
      )
    end
    order by ranked.rank
  ), '[]'::jsonb)
  into v_hits
  from public.firms f
  join (
    select id, row_number() over (order by coalesce(list_score_exact, list_score) desc nulls last, name) as rank
    from public.firms
    where published and indexable and not is_test
  ) ranked on ranked.id = f.id
  where f.name ilike '%' || cleaned || '%'
     or f.slug ilike '%' || cleaned || '%';

  return v_hits;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.public_site_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'firms', coalesce((select jsonb_agg(to_jsonb(f) order by f.list_sort, f.slug) from firms f where f.published and f.indexable and not f.is_test), '[]'::jsonb),
    'site_stats', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from site_stats t), '[]'::jsonb),
    'site_updates', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from site_updates t), '[]'::jsonb),
    'fragments', coalesce((select jsonb_object_agg(key, html) from site_fragments), '{}'::jsonb)
  );
$function$
;

CREATE OR REPLACE FUNCTION public.published_site_core()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with pub as (
    select id from firms where published and indexable and not is_test
  ),
  pub_matters as (
    select distinct matter_id as id from legal_matter_firms where firm_id in (select id from pub)
  ),
  pub_cards as (
    select id from evidence_cards where firm_id in (select id from pub)
  ),
  pub_sources as (
    select distinct source_id as id from fact_sources where firm_id in (select id from pub)
  ),
  pub_people as (
    select person_id as id from fund_people where firm_id in (select id from pub)
    union
    select founder_person_id from reviews where firm_id in (select id from pub) and founder_person_id is not null
    union
    select partner_person_id from reviews where firm_id in (select id from pub) and partner_person_id is not null
    union
    select board_person_id from investments where firm_id in (select id from pub) and board_person_id is not null
    union
    select cf.person_id from company_founders cf join investments i on i.company_id = cf.company_id where i.firm_id in (select id from pub)
  ),
  pub_companies as (
    select distinct company_id as id from investments where firm_id in (select id from pub)
  ),
  pub_press as (
    select press_item_id as id from press_item_firms where firm_id in (select id from pub)
  ),
  pub_results as (
    select id from score_results where firm_id in (select id from pub)
  ),
  pub_reviews as (
    select id from reviews where firm_id in (select id from pub)
  )
  select jsonb_build_object(
    'firms', coalesce((select jsonb_agg(to_jsonb(t) order by t.list_sort, t.slug) from firms t where t.id in (select id from pub)), '[]'::jsonb),
    'funds', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order, t.name) from funds t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'fund_entities', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from fund_entities t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'people', coalesce((select jsonb_agg(to_jsonb(t) order by t.full_name) from people t where t.id in (select id from pub_people)), '[]'::jsonb),
    'fund_people', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from fund_people t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'portfolio_companies', coalesce((select jsonb_agg(to_jsonb(t) order by t.name) from portfolio_companies t where t.id in (select id from pub_companies)), '[]'::jsonb),
    'company_founders', coalesce((select jsonb_agg(to_jsonb(t)) from company_founders t where t.company_id in (select id from pub_companies)), '[]'::jsonb),
    'investments', coalesce((select jsonb_agg(to_jsonb(t)) from investments t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'reviews', coalesce((
      select jsonb_agg(to_jsonb(t) order by t.reviewed_on nulls last, t.created_at)
      from (
        select
          id, firm_id, fund_id, company_id, founder_person_id, partner_person_id,
          body, first_hand, verification_status, moderation_status, reviewed_on,
          created_at, updated_at, profile_id, anonymous, role_label, round_label,
          would_again, verification_method, connection_type,
          honesty, support_after_check, founder_friendly_terms, responsiveness, hard_times
        from reviews
        where firm_id in (select id from pub)
      ) t
    ), '[]'::jsonb),
    'review_ratings', coalesce((select jsonb_agg(to_jsonb(t)) from review_ratings t where t.review_id in (select id from pub_reviews)), '[]'::jsonb),
    'legal_matters', coalesce((select jsonb_agg(to_jsonb(t)) from legal_matters t where t.id in (select id from pub_matters)), '[]'::jsonb),
    'legal_matter_firms', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from legal_matter_firms t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'legal_matter_parties', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from legal_matter_parties t where t.matter_id in (select id from pub_matters)), '[]'::jsonb),
    'filings', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from filings t where t.matter_id in (select id from pub_matters)), '[]'::jsonb),
    'docket_entries', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from docket_entries t where t.matter_id in (select id from pub_matters)), '[]'::jsonb),
    'legal_groups', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from legal_groups t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'legal_group_items', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from legal_group_items t where t.group_id in (select id from legal_groups where firm_id in (select id from pub))), '[]'::jsonb),
    'regulatory_records', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from regulatory_records t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'sanctions_checks', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from sanctions_checks t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'press_items', coalesce((select jsonb_agg(to_jsonb(t)) from press_items t where t.id in (select id from pub_press)), '[]'::jsonb),
    'press_item_firms', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from press_item_firms t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'sources', coalesce((select jsonb_agg(to_jsonb(t)) from sources t where t.id in (select id from pub_sources)), '[]'::jsonb),
    'fact_sources', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from fact_sources t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'takeaways', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from takeaways t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'ask_questions', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from ask_questions t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'copy_blocks', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from copy_blocks t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'page_chips', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from page_chips t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'firm_meta_items', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from firm_meta_items t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'list_items', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from list_items t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'portfolio_metrics', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from portfolio_metrics t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'firm_ranks', coalesce((select jsonb_agg(to_jsonb(t)) from firm_ranks t where t.firm_id in (select id from pub) and t.is_current), '[]'::jsonb),
    'evidence_cards', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from evidence_cards t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'evidence_lines', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from evidence_lines t where t.card_id in (select id from pub_cards)), '[]'::jsonb),
    'score_versions', coalesce((select jsonb_agg(to_jsonb(t)) from score_versions t), '[]'::jsonb),
    'score_sections', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from score_sections t), '[]'::jsonb),
    'score_results', coalesce((select jsonb_agg(to_jsonb(t)) from score_results t where t.id in (select id from pub_results)), '[]'::jsonb),
    'score_result_parts', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from score_result_parts t where t.result_id in (select id from pub_results)), '[]'::jsonb),
    'score_lines', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from score_lines t where t.result_id in (select id from pub_results)), '[]'::jsonb),
    'score_inputs', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from score_inputs t where t.result_id in (select id from pub_results)), '[]'::jsonb),
    'site_stats', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from site_stats t), '[]'::jsonb),
    'site_updates', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from site_updates t), '[]'::jsonb)
  );
$function$
;

CREATE OR REPLACE FUNCTION public.published_site_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with pub as (
    select id, slug from firms where published and indexable and not is_test
  )
  select public.published_site_core() || jsonb_build_object(
    'vc_source_facts', coalesce((select jsonb_agg(to_jsonb(t) || jsonb_build_object('slug', p.slug) order by p.slug, t.section, t.created_at, t.id)
      from vc_source_facts t join pub p on p.id = t.firm_id where t.data_status = 'real' and t.superseded_by is null), '[]'::jsonb),
    'vc_entity_identifiers', coalesce((select jsonb_agg(to_jsonb(t) || jsonb_build_object('slug', p.slug) order by p.slug, t.id_type, t.value)
      from vc_entity_identifiers t join pub p on p.id = t.firm_id where t.data_status = 'real'), '[]'::jsonb),
    'vc_partner_history', coalesce((select jsonb_agg(to_jsonb(t) || jsonb_build_object('slug', p.slug) order by p.slug, t.person_name, t.id)
      from vc_partner_history t join pub p on p.id = t.firm_id where t.data_status = 'real'), '[]'::jsonb),
    'vc_political_activity', coalesce((select jsonb_agg(to_jsonb(t) || jsonb_build_object('slug', p.slug) order by p.slug, t.person_name, t.id)
      from vc_political_activity t join pub p on p.id = t.firm_id where t.data_status = 'real'), '[]'::jsonb),
    'vc_context_notes', coalesce((select jsonb_agg(to_jsonb(t) || jsonb_build_object('slug', p.slug) order by p.slug, t.retrieved_at, t.value)
      from vc_context_notes t join pub p on p.id = t.firm_id where t.data_status = 'real'), '[]'::jsonb)
  );
$function$
;

-- New queue entries get their 'Not checked yet' page right away (exact lookups only, no fuzzy matching).
create or replace function public.research_queue_page_trg() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.duplicate_of is not null or new.status = 'skipped' then return null; end if;
  begin
    perform ensure_firm_for_registry(new.registry_id, false);
  exception when others then
    raise warning 'research_queue_page %: %', new.registry_id, sqlerrm;  -- never block a queue insert
  end;
  return null;
end $$;
revoke all on function public.research_queue_page_trg() from public, anon, authenticated;
drop trigger if exists research_queue_page on public.research_queue;
create trigger research_queue_page after insert on public.research_queue for each row execute function public.research_queue_page_trg();

-- Backfill (set-based, idempotent).
-- 1) hidden firm rows that match a not-yet-researched queue entry by registry_id / CRD become unchecked pages
update firms f set published = true, indexable = false, registry_id = coalesce(f.registry_id, q.registry_id)
from research_queue q
where not f.published and f.deleted_at is null and not coalesce(f.is_test, false) and f.data_status = 'real'
  and q.duplicate_of is null and q.status <> 'skipped'
  and (f.registry_id = q.registry_id or (f.registry_id is null and nullif(q.sec_crd, '') is not null and f.sec_crd = q.sec_crd
       and not exists (select 1 from firms o where o.registry_id = q.registry_id)))
  and not exists (select 1 from research_submissions s where s.registry_id = q.registry_id and s.valid);

-- 2) one new page per remaining entry; slug clashes get -2, -3 ... then a short hash
with c as (
  select q.registry_id t, q.priority, q.name, coalesce(firm_display_name(q.name), q.name) dn, nullif(q.sec_crd, '') crd, q.firm_type,
         firm_hq_format(q.hq_city, q.state, q.country) hq,
         substring(lower(btrim(coalesce(q.website, ''))) from '^(?:[a-z]+://)?(?:www\.)?([^/:?#\s]+)') dom
  from research_queue q
  where q.duplicate_of is null and q.status <> 'skipped'
    and not exists (select 1 from research_submissions s where s.registry_id = q.registry_id and s.valid)
    and not exists (select 1 from firms f where f.registry_id = q.registry_id)
    and (nullif(q.sec_crd, '') is null or not exists (select 1 from firms f where f.sec_crd = q.sec_crd))
), b as (
  select c.*, coalesce(_slugify(dn), lower(t)) base,
         row_number() over (partition by coalesce(_slugify(dn), lower(t)) order by priority, t) rn from c
), s1 as (
  select b.*, case when rn = 1 and not exists (select 1 from firms where slug = b.base) then base else base || '-' || (rn + 1) end cand from b
), s2 as (
  select s1.*, row_number() over (partition by cand order by rn) rn2 from s1
), ins as (
  insert into firms (slug, name, display_name, legal_name, hq, sec_crd, primary_domain, firm_type, data_status, source_system, external_id,
                     registry_id, published, indexable)
  select case when rn2 = 1 and not exists (select 1 from firms where slug = cand) then cand else base || '-' || left(md5(t), 6) end,
         dn, dn, name, hq, crd,
         case when dom ~ '\.' and dom !~ '(^|\.)(linkedin|x|twitter|instagram|facebook|youtube|crunchbase|medium|github|angel|wellfound|pitchbook)\.(com|co|io)$' then dom end,
         case when firm_type = 'vc' then 'VC' end, 'real', 'research', t, t, true, false
  from s2
  returning id
)
insert into firm_check_rows (firm_id, n, title, descr, state, count_label)
select ins.id, x.n, x.title, x.descr, 'nc', null from ins, (values
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

-- 3) link earlier search log rows to the new pages (exact registry_id; no research data touched)
update search_log l set firm_id = f.id from firms f
where l.firm_id is null and not f.indexable and l.registry_id = f.registry_id;

-- 4) keep the queue / SEC legal name searchable as an alias, like ensure_firm_for_registry does
insert into firm_aliases (firm_id, alias, source)
select f.id, btrim(f.legal_name), x.source from firms f, (values ('queue_name'), ('sec_legal')) x(source)
where not f.indexable and coalesce(btrim(f.legal_name), '') <> ''
on conflict do nothing;
