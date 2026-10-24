-- Straight checks (approved 2026-10-23, "for now", no review step): a valid bot upload fills the firm's 10 check rows.
-- Plan: toxybase/plans/straight-checks.md. Rules:
--  * finding = a record referenced by a mapped coverage item (or whose checklist_item maps) that is not a no_match screen,
--    not name-only / different person, not a non-party, and where the firm is not a bystander/victim/creditor/backed company.
--    Only matter-type records count (lawsuits, regulatoryActions, controversies, sanctions, politicalContext).
--    review = severity high/medium or open/pending; wk = any other finding. Political ties: review only if severity high.
--  * clear (check 10: nf) = no findings, every firm/partner-scoped mapped item searched with nothing found, and at least one
--    of them searched against a named source (named registry/list/API tool, or a kept URL on an official domain).
--    Never clear what wasn't searched. LP/company-scoped items that were not searched don't block (and don't count).
--  * registration (8): clear when a registration record (CRD/status) is confirmed via Form ADV / IAPD with no issue;
--    review when lapsed/terminated/withdrawn/revoked/cancelled/inactive; wk on a name mismatch (collisions).
--  * searched_at = latest search_log.executed_at of the queries behind the check's coverage items (coverage items carry
--    no date of their own); if none parse, the submission's received_at; null when the upload had no item for the check.
--  * research_submissions is only read, never changed: firm_check_rows is a display layer and can be re-derived.
--  * everything else = nc ("Not checked yet"). Never downgrade an existing non-nc row to nc.

create or replace function public._ck_n(p_item text) returns int language sql immutable as $$
  select case
    when b ~ '^reg\.sanctions x ' then 1
    when b ~ '^sanctions\.terrorism x ' then 2
    when b ~ '^sanctions\.export x firm' then 3
    when b ~ '^(reg\.securities|reg\.agency|reg\.foreign) x (firm|company)' then 4
    when b ~ '^sanctions\.aml x firm' then 5
    when b ~ '^(legal\.lawsuit|legal\.criminal|fraud\.fraud|fraud\.misrepresentation) x firm' or b = 'g legal matter fields' then 6
    when b ~ '^courts\.worldwide x firm' then 7
    when b ~ '^registration x firm' or b = 'a5 registration check' then 8
    when b ~ '^(people_screen|legal\.lawsuit|legal\.criminal|fraud\.fraud|reg\.securities|workplace\.misconduct) x partner' or b = 'b4 people_screen' then 9
    when b ~ '^(gov\.pep|reg\.pep) x partner' or b ~ '^conduct\.political x (firm|partner)' or b ~ '^lobbying x firm' then 10
  end from (select lower(trim(split_part(coalesce(p_item, ''), ':', 1))) b) s $$;

-- named source: a specific registry / list / API, or an official-domain URL. Generic web search alone is not.
create or replace function public._ck_named(q jsonb) returns boolean language sql immutable as $$
  select lower(coalesce(q->>'tool', '')) ~ '^(sanctions|opensanctions|ofac|courtlistener|uk_caselaw|uk_find_case_law|form_adv|iapd|adviserinfo|sec_|edgar|finra|gleif|fec|senate_lda|lda|lobbying|propublica|regulator_site|pacer)'
      or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(q->'kept_urls') = 'array' then q->'kept_urls' else '[]' end) u
                 where lower(u) ~ '^https?://([^/:?#]*\.)?(gov|gov\.uk|europa\.eu|un\.org)([/:?#]|$)') $$;

create or replace function public._ck_finding(r jsonb) returns boolean language sql immutable as $$
  select coalesce(r->>'field_path', '') in ('lawsuits', 'regulatoryActions', 'controversies', 'sanctions', 'politicalContext')
     and coalesce(v->>'action_type', '') <> 'registration' and lower(coalesce(v->>'status', '')) !~ '^(registered|exempt reporting)'
     and coalesce(v->>'result', '') not in ('no_match', 'not_found', 'none')
     and coalesce(v->>'non_party', 'false') <> 'true'
     and lower(coalesce(v->>'firm_role', '')) !~ '^(bystander|victim|creditor|backed|non_party)'
     and r::text !~* 'different (person|people)|surname-only|name-only hit|name-order variant|not treated as a match|similar name'
  from (select coalesce(r->'value', '{}') v) s $$;

create or replace function public._ck_non_us(r jsonb) returns boolean language sql immutable as $$
  select concat_ws(' ', r->'value'->>'court', r->'value'->>'jurisdiction') ~*
    '\m(UK|U\.K\.|England|London|Wales|Scotland|Ireland|EWHC|EWCA|UKSC|Canada|Ontario|Quebec|Germany|France|Sweden|Switzerland|India|China|Hong Kong|Singapore|Japan|Australia|Israel|Brazil|Cayman|Luxembourg|Netherlands|European)\M' $$;

alter table public.firm_check_rows add column if not exists searched_at timestamptz;
alter table public.firm_check_rows add column if not exists source_submission bigint;

create or replace function public._ck_ts(t text) returns timestamptz language plpgsql immutable as $$
begin return t::timestamptz; exception when others then return null; end $$;

-- 10 rows (n, state, count_label, searched_at) derived from one upload.
drop function if exists public.checks_from_submission(bigint);
create or replace function public.checks_from_submission(p_sub bigint)
returns table (n int, state text, count_label text, searched_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare p jsonb; rcv timestamptz;
begin
  select s.payload, s.received_at into p, rcv from research_submissions s where s.id = p_sub and s.valid;
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
      from lnk where cn <> 8 and _ck_finding(r)),
  item as (
    select covm.*, (covm.st = 'none_found' or (covm.st = 'records'
              and not exists (select 1 from item_recs ir where ir.c = covm.c and _ck_finding(ir.r)))) searched_empty,
           exists (select 1 from lg where lg.qid in (select jsonb_array_elements_text(case when jsonb_typeof(covm.c->'query_ids') = 'array' then covm.c->'query_ids' else '[]' end)) and _ck_named(lg.q)) named
      from covm where not covm.sub),
  reg as (
    select ir.r, (select bool_or(_ck_named(lg.q)) from lg where lg.qid in (select jsonb_array_elements_text(case when jsonb_typeof(ir.c->'query_ids') = 'array' then ir.c->'query_ids' else '[]' end))) named
      from item_recs ir where _ck_n(ir.c->>'checklist_item') = 8),
  regv as (
    select bool_or(concat_ws(' ', r->'value'->>'registration_status', r->'value'->>'status') ~* 'laps|terminat|withdr|revok|cancel|inactive|not registered|expired|suspend|deregist') lapsed,
           bool_or(jsonb_typeof(r->'value'->'collisions') = 'array' and jsonb_array_length(r->'value'->'collisions') > 0) mismatch,
           bool_or((nullif(r->'value'->>'crd', '') is not null or nullif(r->'value'->>'registration_status', '') is not null
                    or (r->'value'->>'action_type' = 'registration' and nullif(r->'value'->>'status', '') is not null))
                   and (coalesce(named, false) or r::text ~* 'adviserinfo\.sec\.gov|form adv|form_adv')) confirmed
      from reg),
  dt as (
    select covm.cn k, max(_ck_ts(lg.q->>'executed_at')) ts from covm
      left join lg on lg.qid in (select jsonb_array_elements_text(case when jsonb_typeof(covm.c->'query_ids') = 'array' then covm.c->'query_ids' else '[]' end))
     group by covm.cn),
  agg as (
    select g.k,
      (select count(*) from fnd where fnd.k = g.k) nf_,
      (select bool_or(case when g.k = 10 then sev = 'high' else sev in ('high', 'medium') or rst ~ '^(open|pending|active|ongoing|filed)' end) from fnd where fnd.k = g.k) rev,
      (select count(*) from item where item.cn = g.k and (item.scope in ('firm', 'partner') or g.k in (9, 10))) req_n,
      (select bool_and(item.searched_empty) from item where item.cn = g.k and (item.scope in ('firm', 'partner') or g.k in (9, 10))) req_ok,
      (select bool_or(item.searched_empty and item.named) from item where item.cn = g.k) named_ok
    from generate_series(1, 10) g(k))
  select a.k, s.state, s.lbl, case when dt.k is not null then coalesce(dt.ts, rcv) end from agg a cross join regv left join dt on dt.k = a.k
    cross join lateral (select case
      when a.k = 8 then case when regv.lapsed then 'review' when regv.mismatch then 'wk' when regv.confirmed then 'clear' else 'nc' end
      when a.nf_ > 0 then case when a.rev then 'review' else 'wk' end
      when a.req_n > 0 and a.req_ok and a.named_ok then case when a.k = 10 then 'nf' else 'clear' end
      else 'nc' end state,
      case
      when a.k = 8 then case when regv.lapsed then 'Registration lapsed' when regv.mismatch then 'Name mismatch' end
      when a.nf_ > 0 then a.nf_ || ' ' || (case a.k when 4 then 'action' when 6 then 'case' when 7 then 'case' when 10 then 'record' else 'finding' end)
                         || case when a.nf_ = 1 then '' else 's' end
      end lbl) s
  order by a.k;
end $$;
revoke all on function public.checks_from_submission(bigint) from public, anon, authenticated;

-- Apply the firm's latest valid upload. Never downgrades a non-nc row to nc. Returns the submission id used (null = none).
create or replace function public.apply_checks_for_firm(p_firm uuid) returns bigint
language plpgsql security definer set search_path = public as $$
declare qid text; sid bigint;
begin
  qid := _firm_queue_id(p_firm);
  if qid is null then return null; end if;
  select id into sid from research_submissions where registry_id = qid and valid order by id desc limit 1;
  if sid is null then return null; end if;
  insert into firm_check_rows (firm_id, n, title, descr, state, count_label, searched_at, source_submission)
  select p_firm, d.n, t.title, t.descr, d.state, d.count_label, d.searched_at, sid
    from checks_from_submission(sid) d
    join (values (1, 'Sanctions', 'Government lists of people and companies you can''t do business with.'),
                 (2, 'Terrorism financing lists', 'Lists of people and groups linked to funding terrorism.'),
                 (3, 'Export and investment restrictions', 'Trade or investment bans, e.g. deals with military-linked firms.'),
                 (4, 'Financial regulator actions', 'Fines, bans and charges from financial regulators.'),
                 (5, 'Money laundering penalties', 'Anti-money-laundering fines and enforcement.'),
                 (6, 'US court records', 'Federal and state cases, civil and criminal.'),
                 (7, 'Court records worldwide', 'Cases outside the U.S.'),
                 (8, 'Registration check', 'Registered with the regulator as an investment adviser, and active.'),
                 (9, 'People behind the fund', 'Partners and owners, each checked against the lists above.'),
                 (10, 'Political ties', 'People at the firm who held government or political roles.')) t(n, title, descr) on t.n = d.n
  on conflict (firm_id, n) do update set state = excluded.state, count_label = excluded.count_label,
      searched_at = excluded.searched_at, source_submission = excluded.source_submission
   where excluded.state <> 'nc' or firm_check_rows.state = 'nc';
  return sid;
end $$;
revoke all on function public.apply_checks_for_firm(uuid) from public, anon, authenticated;

create or replace function public.checks_from_upload_trg() returns trigger
language plpgsql security definer set search_path = public as $$
declare f uuid;
begin
  if not new.valid then return null; end if;
  for f in select id from firms where deleted_at is null and _firm_queue_id(id) = new.registry_id loop
    begin
      perform apply_checks_for_firm(f);
    exception when others then
      raise warning 'checks_from_upload: submission % firm %: %', new.id, f, sqlerrm;  -- never block an ingest
    end;
  end loop;
  return null;
end $$;
drop trigger if exists checks_from_upload on public.research_submissions;
create trigger checks_from_upload after insert on public.research_submissions
  for each row execute function public.checks_from_upload_trg();

-- firm_page: include the queue status so the page knows before first paint whether a bot is checking right now.
create or replace function public.firm_page(p_slug text, p_anon uuid, p_spend boolean default false)
 returns json language plpgsql security definer set search_path to 'public' as $function$
declare f firms; u json; open boolean; secs jsonb := '[]'; s page_sections; it jsonb; hero jsonb; q research_queue; qid text;
begin
  select * into f from firms where slug = p_slug and deleted_at is null and launch_page;
  if f.id is null then return json_build_object('status', 'not_found'); end if;
  u := unlock_firm(p_slug, p_anon, p_spend);
  open := u->>'status' = 'ok';
  if u->>'status' not in ('ok', 'locked') then return u; end if;
  for s in select * from page_sections where enabled order by sort_order loop
    it := _sec_items(s.key, f.id);
    continue when jsonb_array_length(it) = 0;
    secs := secs || jsonb_build_object('key', s.key, 'title', s.title, 'subtitle', s.subtitle, 'renderer', s.renderer,
      'count', jsonb_array_length(it), 'unit', case when jsonb_array_length(it) = 1 then s.unit_one else s.unit_many end,
      'teaser', it->0->>'head', 'items', case when open then it end);
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('label', hero_label, 'value', hero_value, 'anchor', section,
      'src', _src('firm_profile_facts', id)) order by section desc, sort_order), '[]') into hero
    from firm_profile_facts where firm_id = f.id and hero_label is not null and exists (select 1 from fact_sources where fact_type = 'firm_profile_facts' and fact_id = firm_profile_facts.id);
  qid := _firm_queue_id(f.id);
  if qid is not null then select * into q from research_queue where registry_id = qid; end if;
  return json_build_object('status', 'ok', 'open', open,
    'firm', json_build_object('slug', f.slug, 'name', f.name, 'short_name', f.short_name, 'hq', f.hq),
    'hero', hero, 'sections', secs,
    'checks', (select json_agg(json_build_object('n', n, 'title', title, 'descr', descr, 'state', state, 'count', count_label, 'searched_at', searched_at) order by n) from firm_check_rows where firm_id = f.id),
    'queue', q.status, 'started_at', case when q.status = 'claimed' then q.claimed_at end,
    'details', u->'details', 'outline', case when not open then firm_case_outline(p_slug) end);
end $function$;

-- firm_check_status: started_at only while a bot actually holds the claim.
create or replace function public.firm_check_status(p_slug text)
 returns json language plpgsql stable security definer set search_path to 'public' as $function$
declare f firms; q research_queue; qid text;
begin
  select * into f from firms where slug = p_slug and deleted_at is null and launch_page and published;
  if f.id is null then return json_build_object('status', 'not_found'); end if;
  qid := _firm_queue_id(f.id);
  if qid is not null then select * into q from research_queue where registry_id = qid; end if;
  return json_build_object('status', 'ok', 'done', _firm_checks_done(f.id), 'total', 10,
    'complete', _firm_checks_done(f.id) >= 10, 'queue', q.status, 'started_at', case when q.status = 'claimed' then q.claimed_at end,
    'checks', (select json_agg(json_build_object('n', n, 'state', state, 'count', count_label) order by n) from firm_check_rows where firm_id = f.id));
end $function$;

-- Backfill: every live firm's latest valid upload.
select public.apply_checks_for_firm(id) from public.firms where deleted_at is null;
