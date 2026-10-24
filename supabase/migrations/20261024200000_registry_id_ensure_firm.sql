-- Sprint: registry_id link between firms and research_queue, CRD de-dupe of the queue, display names,
-- and ensure_firm_for_registry (every researched registry entry gets a published /vc/<slug>/ page).
-- Backups: /workspace/backups/pre-registry-sprint-2026-10-24/ and schema backup_20261024s12.

-- 1. Name helpers -----------------------------------------------------------------------------------------
create or replace function public._queue_name_key(p text) returns text language sql immutable as $$
  select nullif(regexp_replace(regexp_replace(lower(coalesce(p, '')), '\m(llc|l\.?l\.?c|lp|l\.?p|inc|ltd|management|co)\M', '', 'g'), '[^a-z0-9]', '', 'g'), '')
$$;

-- Clean an SEC registrant name for display: drop legal suffixes (LLC, L.L.C., LP, Inc, Ltd, Management Co, Co., GP ...),
-- title-case, keep brand casing for known names (a16z ...). The SEC name stays in firms.legal_name.
create or replace function public.firm_display_name(p text) returns text language plpgsql immutable as $$
declare s text := btrim(coalesce(p, '')); prev text; w text; out text := ''; brands jsonb := '{"a16z":"a16z","ah":"AH","ab":"AB","qed":"QED","idg":"IDG","rre":"RRE","ra":"RA","ia":"IA","ri":"RI","eqt":"EQT","ew":"EW","avf":"AVF","awm":"AWM","mfo":"MFO","mic":"MIC","ecv":"ECV","bip":"BIP","amr":"AMR","ugp":"UGP","lav":"LAV","sosv":"SOSV","vbi":"VBI","nrep":"NREP","fpv":"FPV","openai":"OpenAI","alliancebernstein":"AllianceBernstein","peakspan":"PeakSpan","ourcrowd":"OurCrowd","healthquest":"HealthQuest","parafi":"ParaFi","mcmorgan":"McMorgan","stepstone":"StepStone","infravia":"InfraVia","venbio":"venBio","truebridge":"TrueBridge","boxgroup":"BoxGroup","signalfire":"SignalFire","multicoin":"Multicoin","greycroft":"Greycroft","ycombinator":"Y Combinator","kkr":"KKR","tpg":"TPG","nea":"NEA","ivp":"IVP","ggv":"GGV","dst":"DST","nfx":"NFX","usv":"USV","bvp":"BVP","dfj":"DFJ","ejf":"EJF","esp":"ESP","hv":"HV","fr":"FR","gv":"GV","vc":"VC","ai":"AI","uk":"UK","usa":"USA","us":"US","ii":"II","iii":"III","iv":"IV","lux":"Lux","mcm":"MCM","ffl":"FFL","dcm":"DCM","jmi":"JMI","tcv":"TCV","abs":"ABS","sv":"SV","kb":"KB","ta":"TA","bv":"BV","hig":"HIG","hggc":"HGGC","gcm":"GCM","lgt":"LGT","ubs":"UBS","jpmorgan":"JPMorgan","blackrock":"BlackRock","openview":"OpenView","bessemer":"Bessemer","firstmark":"FirstMark","redpoint":"Redpoint","lowercase":"Lowercase","emergence":"Emergence"}';
  small text[] := array['of','and','the','for','de','du','la','le','von','van','der','des','et','an','at','on','in'];
  i int := 0;
begin
  if s = '' then return null; end if;
  s := regexp_replace(s, '\s+', ' ', 'g');
  s := regexp_replace(s, '\s*\((f/k/a|formerly|fka)[^)]*\)', '', 'gi');
  s := regexp_replace(s, ',\s*an?\s+[a-z ]*limited liability company\s*$', '', 'i');
  loop
    prev := s;
    s := regexp_replace(s, '[\s,]*\((usa|us|uk|u\.s\.|u\.k\.)\)\s*$', '', 'i');
    s := regexp_replace(s, '\s+mgmt\.?$', '', 'i');
    s := regexp_replace(s, '[\s,]+(private\s+limited|pty\.?\s+ltd\.?|pty\.?|ab)\s*$', '', 'i');
    s := regexp_replace(s, '[\s,]+(l\.?\s?l\.?\s?c\.?|l\.?\s?l\.?\s?p\.?|l\.?\s?p\.?|inc\.?|incorporated|ltd\.?|limited|corp\.?|corporation|gmbh|b\.\s?v\.?|ag|s\.?\s?a\.?|s\.?\s?a\.?\s?r\.?\s?l\.?|s\.?\s?à\.?\s?r\.?\s?l\.?|plc|pte\.?|gp|co\.?|company|management\s+co\.?|management\s+company)\s*$', '', 'i');
    s := regexp_replace(s, '\m(capital|ventures?|partners|venture\s+partners|growth|equity|holdings)\s+management$', '\1', 'i');
    s := regexp_replace(s, '[\s,&\-]+$', '');
    exit when s = prev;
  end loop;
  if s = '' then s := btrim(p); end if;
  if s ~ '[a-z]' and s ~ '[A-Z]' and s !~ '^[A-Z0-9 ,.&''()\-]+$' then return s; end if;  -- already mixed case: keep
  for w in select x from regexp_split_to_table(s, ' ') x loop
    i := i + 1;
    if brands ? lower(regexp_replace(w, '[^A-Za-z0-9]', '', 'g')) and w ~ '^[A-Za-z0-9]+[,.]?$' then
      out := out || ' ' || (brands->>lower(regexp_replace(w, '[^A-Za-z0-9]', '', 'g'))) || regexp_replace(w, '^[A-Za-z0-9]+', '');
    elsif i > 1 and lower(w) = any(small) then out := out || ' ' || lower(w);
    elsif w ~ '^([A-Za-z]\.)+$' or lower(w) ~ '^(ii|iii|iv|vi|vii|viii|ix|xi|xii|xiii|xiv|xv|xvi|xvii|xviii|xix|xx)$' then out := out || ' ' || upper(w);
    elsif w ~ '\d' and length(w) > 3 then out := out || ' ' || initcap(lower(w));
    elsif w ~ '\d' or (length(w) <= 4 and lower(w) !~ '[aeiouy]' and w ~ '^[A-Za-z]+$') then out := out || ' ' || upper(w);
    else out := out || ' ' || initcap(lower(w));
    end if;
  end loop;
  return btrim(out);
end $$;

create or replace function public._slugify(p text) returns text language sql immutable as $$
  select nullif(btrim(regexp_replace(lower(translate(coalesce(p, ''), 'àáâäãåèéêëìíîïòóôöõùúûüçñ', 'aaaaaaeeeeiiiiooooouuuucn')), '[^a-z0-9]+', '-', 'g'), '-'), '')
$$;

-- 2. research_queue: name key, duplicate flag, CRD uniqueness -------------------------------------------------
alter table public.research_queue add column if not exists name_key text generated always as (public._queue_name_key(name)) stored;
alter table public.research_queue add column if not exists duplicate_of text references public.research_queue(registry_id);
create index if not exists research_queue_name_key_idx on public.research_queue(name_key);
create unique index if not exists research_queue_sec_crd_uq on public.research_queue(sec_crd) where sec_crd is not null and sec_crd <> '';
comment on column public.research_queue.duplicate_of is 'Name-only entry that duplicates this CRD entry (status skipped when it was merged; flag only when it already had research).';

-- Flag name-only entries that duplicate a CRD entry; merge (skip) the ones that never got research.
with d as (
  select n.registry_id dup, (select c.registry_id from research_queue c
                               where c.name_key = n.name_key and nullif(c.sec_crd, '') is not null and length(c.name_key) >= 4
                               order by c.priority, c.registry_id limit 1) keep
  from research_queue n where nullif(n.sec_crd, '') is null and n.duplicate_of is null
)
update research_queue q set duplicate_of = d.keep,
  status = case when q.status in ('queued', 'failed') and not exists (select 1 from research_submissions s where s.registry_id = q.registry_id) then 'skipped' else q.status end,
  last_error = case when q.status in ('queued', 'failed') and not exists (select 1 from research_submissions s where s.registry_id = q.registry_id) then 'duplicate of ' || d.keep else q.last_error end
from d where d.dup = q.registry_id and d.keep is not null;
-- the kept entry inherits the better priority
update research_queue c set priority = x.p from (
  select duplicate_of rid, min(priority) p from research_queue where duplicate_of is not null group by 1) x
where c.registry_id = x.rid and x.p < c.priority;

create or replace function public._registry_target(p text) returns text language sql stable security definer set search_path = public as $$
  select coalesce((select duplicate_of from research_queue where registry_id = p), p)
$$;

-- Future inserts: never a second row for a CRD; a name-only row that matches a CRD row is stored as a skipped duplicate;
-- a new CRD row absorbs a still-queued name-only twin.
create or replace function public.research_queue_dedupe_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare k text := _queue_name_key(new.name); keep text;
begin
  if nullif(new.sec_crd, '') is not null then
    if exists (select 1 from research_queue where sec_crd = new.sec_crd and registry_id <> new.registry_id) then return null; end if;
    if length(coalesce(k, '')) >= 4 then
      update research_queue set duplicate_of = new.registry_id,
        status = case when status = 'queued' then 'skipped' else status end,
        last_error = case when status = 'queued' then 'duplicate of ' || new.registry_id else last_error end
      where nullif(sec_crd, '') is null and name_key = k and duplicate_of is null and registry_id <> new.registry_id;
    end if;
  elsif length(coalesce(k, '')) >= 4 and new.duplicate_of is null then
    select registry_id into keep from research_queue where name_key = k and nullif(sec_crd, '') is not null and registry_id <> new.registry_id
      order by priority, registry_id limit 1;
    if keep is not null then
      new.duplicate_of := keep; new.status := 'skipped'; new.last_error := 'duplicate of ' || keep;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists research_queue_dedupe on public.research_queue;
create trigger research_queue_dedupe before insert on public.research_queue for each row execute function public.research_queue_dedupe_trg();

-- 3. firms.registry_id + display_name -------------------------------------------------------------------
alter table public.firms add column if not exists registry_id text references public.research_queue(registry_id) on delete set null;
alter table public.firms add column if not exists display_name text;
create unique index if not exists firms_registry_id_uq on public.firms(registry_id) where registry_id is not null;
comment on column public.firms.registry_id is 'research_queue entry this page is built from (exact link; replaces the fuzzy name match).';
comment on column public.firms.display_name is 'Clean brand name shown on the page, suggestions, titles. legal_name keeps the SEC registrant name.';

-- Fallback matcher (only for firms without registry_id): exact CRD first (NULLs last), then normalized name.
create or replace function public._firm_queue_id(p_firm uuid) returns text language sql stable security definer set search_path = public as $$
  with f as (select * from firms where id = p_firm)
  select coalesce((select registry_id from f),
   (select _registry_target(q.registry_id) from research_queue q, f
     where (nullif(f.sec_crd, '') is not null and q.sec_crd = f.sec_crd)
        or (length(coalesce(_queue_name_key(f.name), '')) >= 4 and q.name_key = _queue_name_key(f.name))
     order by coalesce(nullif(f.sec_crd, '') is not null and q.sec_crd = f.sec_crd, false) desc,
              (nullif(q.sec_crd, '') is not null) desc, q.priority, q.registry_id
     limit 1))
$$;

update firms f set registry_id = x.rid from (
  select id, _firm_queue_id(id) rid from firms where registry_id is null and deleted_at is null and not coalesce(is_test, false)) x
where f.id = x.id and x.rid is not null
  and not exists (select 1 from firms o where o.registry_id = x.rid);
update firms set display_name = name where display_name is null;

-- Triggers use the exact link.
create or replace function public.checks_from_upload_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare f uuid;
begin
  if not new.valid then return null; end if;
  for f in select id from firms where deleted_at is null and registry_id = _registry_target(new.registry_id) loop
    begin
      perform apply_checks_for_firm(f);
    exception when others then
      raise warning 'checks_from_upload: submission % firm %: %', new.id, f, sqlerrm;  -- never block an ingest
    end;
  end loop;
  return null;
end $$;

create or replace function public.promote_bot_facts_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare f uuid;
begin
  if not new.valid then return null; end if;
  for f in select id from firms where deleted_at is null and registry_id = _registry_target(new.registry_id) loop
    begin
      perform promote_bot_facts(f);
    exception when others then
      raise warning 'promote_bot_facts: submission % firm %: %', new.id, f, sqlerrm;  -- never block an ingest
    end;
  end loop;
  return null;
end $$;

-- 4. ensure_firm_for_registry ----------------------------------------------------------------------------
create or replace function public.ensure_firm_for_registry(p_registry text, p_fill boolean default true) returns uuid
language plpgsql security definer set search_path = public as $$
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
      update firms set published = true where id = fid and not published and not coalesce(is_test, false) and data_status = 'real';
    end if;
  else
    dn := coalesce(firm_display_name(q.name), q.name);
    base := coalesce(_slugify(dn), lower(t)); slg := base;
    while exists (select 1 from firms where slug = slg) loop sfx := sfx + 1; slg := base || '-' || sfx; end loop;
    dom := substring(lower(btrim(coalesce(q.website, ''))) from '^(?:[a-z]+://)?(?:www\.)?([^/:?#\s]+)');
    if dom is null or dom !~ '\.' or dom ~ '(^|\.)(linkedin|x|twitter|instagram|facebook|youtube|crunchbase|medium|github|angel|wellfound|pitchbook)\.(com|co|io)$' then dom := null; end if;
    hq := nullif(concat_ws(', ', nullif(initcap(lower(q.hq_city)), ''),
            case when q.country in ('United States', 'US', 'USA') then nullif(q.state, '') else nullif(q.country, '') end), '');
    insert into firms (slug, name, display_name, legal_name, hq, sec_crd, primary_domain, firm_type, data_status, source_system, external_id,
                       registry_id, published)
    values (slg, dn, dn, q.name, hq, nullif(q.sec_crd, ''), dom, case when q.firm_type = 'vc' then 'VC' end, 'real', 'research', t,
            t, researched)
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
  -- link enrichments / search log rows that arrived before the page existed (rows are not copied, so re-sends never duplicate)
  update research_enrichments set firm_id = fid where firm_id is null and registry_id in (t, p_registry);
  get diagnostics linked = row_count;
  update search_log set firm_id = fid where firm_id is null and registry_id in (t, p_registry);
  if p_fill or created then
    begin perform apply_checks_for_firm(fid); exception when others then raise warning 'ensure_firm %: checks: %', t, sqlerrm; end;
    begin perform promote_bot_facts(fid); exception when others then raise warning 'ensure_firm %: bot facts: %', t, sqlerrm; end;
  end if;
  if p_fill or created or linked > 0 then
    begin perform promote_enrichment(fid); exception when others then raise warning 'ensure_firm %: enrichment: %', t, sqlerrm; end;
  end if;
  return fid;
end $$;
revoke all on function public.ensure_firm_for_registry(text, boolean) from public, anon, authenticated;

-- Valid report -> make sure the page exists first (fires before checks_from_upload / promote_bot_facts, alphabetical).
create or replace function public.ensure_firm_trg() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not new.valid then return null; end if;
  begin
    perform ensure_firm_for_registry(new.registry_id, false);
  exception when others then
    raise warning 'ensure_firm: submission % registry %: %', new.id, new.registry_id, sqlerrm;  -- never block an ingest
  end;
  return null;
end $$;
drop trigger if exists aa_ensure_firm on public.research_submissions;
create trigger aa_ensure_firm after insert on public.research_submissions for each row execute function public.ensure_firm_trg();

-- 5. research_enrich: keep the slug the bot sent; create the page for a known registry entry before storing.
create or replace function public.research_enrich(p_bot text, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare fid uuid; reg text := nullif(p_payload->>'registry_id', ''); slg text := nullif(p_payload->>'slug', ''); page text; eid bigint;
  acc int; rej int; errs jsonb; v boolean;
begin
  if slg is not null then select id into fid from firms where slug = slg and deleted_at is null; end if;
  if fid is null and reg is not null then
    select id into fid from firms where deleted_at is null and not coalesce(is_test, false) and registry_id = _registry_target(reg)
     order by published desc limit 1;
    if fid is null and exists (select 1 from research_queue where registry_id = reg) then
      fid := ensure_firm_for_registry(reg, false);
    end if;
  end if;
  if fid is null and reg is null then return jsonb_build_object('error', 'unknown firm: send "slug" (page slug) or "registry_id"'); end if;
  if reg is null then reg := _firm_queue_id(fid); end if;
  select slug into page from firms where id = fid and published;
  select count(*) filter (where ok), count(*) filter (where not ok),
    coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'section', section, 'field', field, 'item', left(txt, 120), 'url', url, 'reason', reason)) filter (where not ok), '[]')
    into acc, rej, errs from enrichment_items(p_payload);
  v := acc > 0;
  insert into research_enrichments(bot_id, registry_id, slug, firm_id, payload, valid, errors, accepted, rejected)
  values (p_bot, reg, coalesce(slg, (select slug from firms where id = fid)), fid, p_payload, v, errs, acc, rej) returning id into eid;
  return jsonb_build_object('enrichment_id', eid, 'firm', coalesce(page, slg), 'registry_id', reg, 'on_page', page is not null, 'valid', v,
    'accepted_items', acc, 'rejected_items', rej, 'rejected', errs);
end $$;

-- 6. Public RPCs show the display name; firm_page also carries the SEC name for /vc/<slug>/full/.
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
    return json_build_object('status', 'ok', 'open', false, 'locked', u->>'status',
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
  return json_build_object('status', 'ok', 'open', true, 'done', _firm_checks_done(f.id),
    'firm', json_build_object('slug', f.slug, 'name', coalesce(f.display_name, f.name), 'sec_name', coalesce(f.legal_name, f.name), 'short_name', f.short_name, 'hq', f.hq),
    'hero', hero, 'sections', secs,
    'checks', (select json_agg(json_build_object('n', n, 'title', title, 'descr', descr, 'state', state, 'count', count_label, 'searched_at', searched_at,
        'items', (select coalesce(json_agg(json_build_object('title', i.title, 'year', i.yr, 'status', i.status, 'note', i.note, 'who', i.who) order by i.yr desc nulls last, i.title), '[]') from check_findings(source_submission) i where i.k = n),
        'itemized', (select count(*) from check_findings(source_submission) i where i.k = n)) order by n) from firm_check_rows where firm_id = f.id),
    'queue', q.status, 'started_at', case when q.status = 'claimed' then q.claimed_at end,
    'details', u->'details', 'outline', null);
end $function$
;

CREATE OR REPLACE FUNCTION public.firm_meta(p_slug text)
 RETURNS TABLE(slug text, name text, short_name text, hq text, firm_type text, legal_name text, primary_domain text, founded_year integer, updated_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select f.slug, coalesce(f.display_name, f.name), f.short_name, f.hq, f.firm_type, f.legal_name, f.primary_domain, f.founded_year::int, f.updated_at
  from public.firms f
  where f.slug = lower(p_slug) and f.published and not coalesce(f.is_test, false)
    and f.deleted_at is null and f.data_status = 'real'
  limit 1
$function$
;

CREATE OR REPLACE FUNCTION public.firm_suggest(q text)
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with t as (select lower(trim(q)) t), m as (
    select f.slug, coalesce(f.display_name, f.name) as name, f.short_name, f.hq,
      case when lower(coalesce(f.display_name, f.name)) like t || '%' or lower(coalesce(f.short_name, '')) like t || '%' or f.slug like t || '%' then 0
           when lower(coalesce(f.display_name, f.name)) ~ ('\m' || regexp_replace(t, '([^a-z0-9 ])', '\\\1', 'g')) then 1 else 2 end r
    from firms f, t
    where f.published and not coalesce(f.is_test, false) and f.data_status = 'real' and f.deleted_at is null and length(t) > 0
      and (lower(coalesce(f.display_name, f.name)) like '%' || t || '%' or lower(coalesce(f.short_name, '')) like '%' || t || '%' or f.slug like '%' || t || '%'))
  select coalesce(json_agg(json_build_object('slug', slug, 'name', name, 'short_name', short_name, 'hq', hq) order by r, name), '[]')
  from (select * from m order by r, name limit 8) x
$function$

;
