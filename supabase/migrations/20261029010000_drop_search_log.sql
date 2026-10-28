-- Remove bots.search_log (347 MB): a copy of search lists already stored in bots.research_submissions payloads.
-- Approved by Alex 2026-10-28 09:23 PT. No export. Rollback: supabase/rollbacks/20261029010000_drop_search_log.sql
-- check_findings, checks_from_submission and _door_key only read the payload key 'search_log', not the table: untouched.

select cron.unschedule('bots-search-log-retention') where exists (select 1 from cron.job where jobname = 'bots-search-log-retention');

drop trigger if exists submission_search_log on bots.research_submissions;
drop function if exists public._submission_search_log();
drop function if exists public.search_log_from_submission(bigint);
drop function if exists bots.purge_old_search_log();

-- Enrichment trigger: stop writing search_log.
CREATE OR REPLACE FUNCTION public._enrichment_after_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'bots', 'public'
AS $function$
declare hold boolean := false;
begin
  if new.valid and new.bot_id = 'toxy-enricher' and new.firm_id is not null then
    if to_regprocedure('public._checker_publish_on()') is not null then
      execute 'select public._checker_publish_on() and public._lab_firm($1)' into hold using new.firm_id;
    end if;
    if hold then
      perform set_config('app.finder_holding', '1', true);
      begin
        insert into research_submissions(bot_id, registry_id, payload, record_count, valid, errors)
        values (new.bot_id, new.registry_id, new.payload, new.accepted, coalesce(new.valid, false), new.errors);
      exception when others then
        if to_regclass('bots.checker_holding') is not null then
          execute 'insert into bots.checker_holding(firm_id, origin, origin_id, kind, outcome, reason, item) values ($1,$2,$3,$4,$5,$6,$7)'
            using new.firm_id, 'enrichment', new.id, 'row', 'failure', sqlerrm, new.payload;
        end if;
      end;
      perform set_config('app.finder_holding', '', true);
    else
      perform promote_enrichment(new.firm_id);
    end if;
  end if;
  if new.valid then
    perform refresh_feedback_patterns();
  end if;
  return null;
end $function$;

-- ensure_firm_for_registry: stop linking search_log rows.
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

drop function if exists public.search_log_from_enrichment(bigint);

-- Views: drop the search_log reports; keep firm_section_status (read by next_firms_to_enrich) without search_log.
drop view if exists public.site_search_stats;
drop view if exists public.firm_site_coverage;
create or replace view public.firm_section_status as
 WITH fq AS (
         SELECT f.id AS firm_id,
            f.slug,
            f.name,
            f.published,
            _firm_queue_id(f.id) AS registry_id
           FROM firms f
          WHERE ((f.deleted_at IS NULL) AND (NOT COALESCE(f.is_test, false)) AND (f.published OR f.launch_page))
        ), base AS (
         SELECT fq.firm_id,
            fq.slug,
            fq.name,
            fq.published,
            fq.registry_id,
            s.sec,
                CASE
                    WHEN (fq.firm_id IS NULL) THEN false
                    WHEN (s.sec = 'checks'::text) THEN (EXISTS ( SELECT 1
                       FROM firm_check_rows c
                      WHERE ((c.firm_id = fq.firm_id) AND (c.source_submission IS NOT NULL))))
                    WHEN (s.sec = 'board_seats'::text) THEN (EXISTS ( SELECT 1
                       FROM firm_people_roles p
                      WHERE ((p.firm_id = fq.firm_id) AND (p.kind = 'board'::text) AND (EXISTS ( SELECT 1
                               FROM fact_sources x
                              WHERE ((x.fact_type = 'firm_people_roles'::text) AND (x.fact_id = p.id)))))))
                    ELSE (jsonb_array_length(_sec_items(s.sec, fq.firm_id)) > 0)
                END AS filled
           FROM (fq
             CROSS JOIN ( VALUES ('overview'::text), ('checks'::text), ('legal'::text), ('people'::text), ('board_seats'::text), ('funds'::text), ('timeline'::text), ('press'::text), ('founders'::text)) s(sec))
        ), sec AS (
         SELECT b.firm_id,
            b.slug,
            b.name,
            b.published,
            b.registry_id,
            b.sec AS item,
                CASE
                    WHEN b.filled THEN 'filled'::text
                    ELSE 'missing'::text
                END AS status,
            NULL::timestamp with time zone AS last_searched
           FROM base b
        ), chk AS (
         SELECT DISTINCT fq.firm_id,
            fq.slug,
            fq.name,
            fq.published,
            fq.registry_id,
            ('checklist:'::text || (c.value ->> 'checklist_item'::text)) AS item,
                CASE
                    WHEN ((c.value ->> 'status'::text) = 'blocked'::text) THEN 'blocked'::text
                    ELSE 'not_searched'::text
                END AS status,
            NULL::timestamp with time zone AS last_searched
           FROM (fq
             JOIN LATERAL ( SELECT s.payload
                   FROM bots.research_submissions s
                  WHERE ((s.registry_id = fq.registry_id) AND s.valid)
                  ORDER BY s.received_at DESC, s.id DESC
                 LIMIT 1) ls ON (true)),
            LATERAL jsonb_array_elements(COALESCE((ls.payload -> 'coverage'::text), '[]'::jsonb)) c(value)
          WHERE ((c.value ->> 'status'::text) = ANY (ARRAY['blocked'::text, 'not_searched'::text]))
        ), allx AS (
         SELECT sec.firm_id,
            sec.slug,
            sec.name,
            sec.published,
            sec.registry_id,
            sec.item,
            sec.status,
            sec.last_searched
           FROM sec
        UNION ALL
         SELECT chk.firm_id,
            chk.slug,
            chk.name,
            chk.published,
            chk.registry_id,
            chk.item,
            chk.status,
            chk.last_searched
           FROM chk
        )
 SELECT firm_id,
    slug,
    name,
    published,
    registry_id,
    item,
    status,
    last_searched,
    count(*) FILTER (WHERE (status = ANY (ARRAY['filled'::text, 'searched_none'::text]))) OVER w AS done,
    count(*) OVER w AS total,
    round(((count(*) FILTER (WHERE (status = ANY (ARRAY['filled'::text, 'searched_none'::text]))) OVER w)::numeric / (count(*) OVER w)::numeric), 3) AS score
   FROM allx a
  WINDOW w AS (PARTITION BY COALESCE((firm_id)::text, registry_id));
drop view if exists bots.search_log_current;

drop table if exists bots.search_log;
drop table if exists backup_20261024s12.search_log_firm;
