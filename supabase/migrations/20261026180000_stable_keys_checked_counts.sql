-- Step 5: stable keys, last-checked metadata and a per-section row-count alert.
-- (a) stable_key (generated, so existing rows are backfilled without touching their data) on people, legal, timeline and
--     fund facts; deals reuse investments.dedupe_key and the funds table reuses funds.dedupe_key. Promote matches on the
--     key to merge instead of adding a duplicate. Existing collisions are only reported (stable_key_collisions()), never merged.
-- (b) last_checked_at / checked_source on the item tables, null for existing rows (no invented dates); set when the
--     checker publishes or re-confirms (merges) an item.
-- (c) section_count_alerts: after any promote, per-section counts are compared with the previous counts. An internal
--     table, not notify-checks (that Edge Function emails visitors, so it is not reused for ops alerts).

create or replace function public._person_key(n text) returns text language sql immutable as $$
  select nullif(_norm_txt(regexp_replace(lower(coalesce(n, '')), '^\s*(dr|mr|mrs|ms|prof|sir)\.?\s+', '')), '') $$;

create or replace function public._legal_key(t text) returns text language sql immutable as $$
  select coalesce(
    'case:' || regexp_replace(substring(lower(coalesce(t, '')) from '\m(?:\d{1,2}:)?(\d{2}-[a-z]{2,4}-\d{3,6})\M'), '[^a-z0-9]', '', 'g'),
    'file:' || substring(lower(coalesce(t, '')) from '\mfile no\.?\s*((?:3|33|34|ia|ic)-\d{4,6})\M'),
    'cap:' || nullif(_norm_txt(regexp_replace(regexp_replace(coalesce(t, ''), '^\s*((lead|correction)(\s*\([^)]*\))?\s*:\s*)+', '', 'i'), '\s*\((?:[^()]*\m(?:cal|n\.?y|del|tex|fla|ill|mass|cir|ct)\.?[^()]*)\)', '', 'gi')), '')) $$;

create or replace function public._fund_key(v text) returns text language sql immutable as $$
  select coalesce(
    'file:' || substring(lower(coalesce(v, '')) from '\m((?:021|811|801|814)-\d{4,6})\M'),
    'name:' || nullif(_norm_txt(regexp_replace(split_part(coalesce(v, ''), ' · ', 1), '[,.]?\s*\m(l\.?\s?p\.?|llc|ltd|l\.?\s?l\.?\s?c\.?)\s*$', '', 'i')), '')) $$;

create or replace function public._timeline_key(d text, body text) returns text language sql immutable as $$
  select coalesce(substring(coalesce(d, '') from '(\d{4})'), 'undated') || '|' || _norm_txt(_fp_text(body)) $$;

alter table public.firm_people_roles add column if not exists stable_key text generated always as (_person_key(person_name)) stored;
alter table public.firm_legal_items  add column if not exists stable_key text generated always as (_legal_key(title)) stored;
alter table public.timeline_events   add column if not exists stable_key text generated always as (_timeline_key(date_label, body)) stored;
alter table public.firm_profile_facts add column if not exists stable_key text generated always as (case when section = 'funds' then _fund_key(value) end) stored;
create index if not exists firm_people_roles_stable_key on public.firm_people_roles(firm_id, stable_key);
create index if not exists firm_legal_items_stable_key on public.firm_legal_items(firm_id, stable_key);
create index if not exists timeline_events_stable_key on public.timeline_events(firm_id, stable_key);
create index if not exists firm_profile_facts_stable_key on public.firm_profile_facts(firm_id, stable_key) where stable_key is not null;

-- read-only: existing rows that share a key (reported, never merged)
create or replace function public.stable_key_collisions()
 returns table(tbl text, firm_id uuid, slug text, stable_key text, n bigint)
 language sql stable security definer set search_path = public as $$
  select x.tbl, x.firm_id, f.slug, x.k, x.n from (
    select 'firm_people_roles' tbl, firm_id, kind || '|' || stable_key k, count(*) n from firm_people_roles where stable_key is not null group by 1, 2, 3 having count(*) > 1
    union all select 'firm_legal_items', firm_id, stable_key, count(*) from firm_legal_items where stable_key is not null group by 1, 2, 3 having count(*) > 1
    union all select 'timeline_events', firm_id, stable_key, count(*) from timeline_events where stable_key is not null group by 1, 2, 3 having count(*) > 1
    union all select 'firm_profile_facts(funds)', firm_id, stable_key, count(*) from firm_profile_facts where stable_key is not null group by 1, 2, 3 having count(*) > 1
    union all select 'funds', firm_id, dedupe_key, count(*) from funds where dedupe_key is not null group by 1, 2, 3 having count(*) > 1
    union all select 'investments', firm_id, dedupe_key, count(*) from investments where dedupe_key is not null group by 1, 2, 3 having count(*) > 1
  ) x left join firms f on f.id = x.firm_id $$;
revoke execute on function public.stable_key_collisions() from public, anon, authenticated;

-- (b) last checked
alter table public.firm_people_roles add column if not exists last_checked_at timestamptz, add column if not exists checked_source text;
alter table public.firm_legal_items  add column if not exists last_checked_at timestamptz, add column if not exists checked_source text;
alter table public.timeline_events   add column if not exists last_checked_at timestamptz, add column if not exists checked_source text;
alter table public.firm_profile_facts add column if not exists last_checked_at timestamptz, add column if not exists checked_source text;
alter table public.press_item_firms  add column if not exists last_checked_at timestamptz, add column if not exists checked_source text;

create or replace function public._mark_checked() returns trigger language plpgsql security definer set search_path = public as $$
declare u text := left(coalesce(new.item->>'source', new.item->>'source_url', new.item->>'url'), 1000);
begin
  if new.outcome not in ('published', 'merged') or new.target_id is null or coalesce(new.reason, 'already') !~ '^already' then return null; end if;
  if new.target_table = 'press_item_firms' then
    update press_item_firms set last_checked_at = now(), checked_source = u where press_item_id = new.target_id and firm_id = new.firm_id;
  elsif new.target_table in ('firm_people_roles', 'firm_legal_items', 'timeline_events', 'firm_profile_facts') then
    execute format('update %I set last_checked_at = now(), checked_source = $1 where id = $2 and firm_id = $3', new.target_table)
      using u, new.target_id, new.firm_id;
  end if;
  return null;
end $$;
drop trigger if exists mark_checked on public.publish_checks;
create trigger mark_checked after insert on public.publish_checks for each row execute function public._mark_checked();

-- (c) row-count alert
create table if not exists public.section_counts (
  firm_id uuid not null, section text not null, n int not null, counted_at timestamptz not null default now(),
  primary key (firm_id, section));
create table if not exists public.section_count_alerts (
  id bigserial primary key, firm_id uuid not null, section text not null, prev_n int not null, new_n int not null,
  kind text not null check (kind in ('drop', 'jump')), origin text, created_at timestamptz not null default now());
alter table public.section_counts enable row level security;
alter table public.section_count_alerts enable row level security;
revoke all on public.section_counts, public.section_count_alerts from anon, authenticated;

create or replace function public._section_counts_now(p_firm uuid) returns table(section text, n int)
 language sql stable set search_path = public as $$
  select s, coalesce(c, 0)::int from unnest(array['overview', 'funds', 'lps', 'legal', 'timeline', 'people', 'press']) s
  left join (
    select x.section s2, count(*) c from firm_profile_facts x where x.firm_id = p_firm and not x.hidden group by 1
    union all select 'legal', count(*) from firm_legal_items where firm_id = p_firm and not hidden
    union all select 'timeline', count(*) from timeline_events where firm_id = p_firm and not hidden
    union all select 'people', count(*) from firm_people_roles where firm_id = p_firm and not hidden
    union all select 'press', count(*) from press_item_firms where firm_id = p_firm and not hidden
  ) q on q.s2 = s $$;

-- drop: any decrease. jump: up by more than 20, or by more than 50% of a non-zero previous count.
create or replace function public._section_count_check(p_firm uuid, p_origin text) returns int
 language plpgsql security definer set search_path = public as $$
declare r record; k int := 0;
begin
  if p_firm is null then return 0; end if;
  for r in select c.section, c.n, p.n prev from _section_counts_now(p_firm) c
           left join section_counts p on p.firm_id = p_firm and p.section = c.section loop
    if r.prev is not null and (r.n < r.prev or r.n - r.prev > 20 or (r.prev > 0 and r.n > r.prev * 1.5)) then
      insert into section_count_alerts(firm_id, section, prev_n, new_n, kind, origin)
      values (p_firm, r.section, r.prev, r.n, case when r.n < r.prev then 'drop' else 'jump' end, p_origin);
      k := k + 1;
    end if;
    insert into section_counts(firm_id, section, n, counted_at) values (p_firm, r.section, r.n, now())
    on conflict (firm_id, section) do update set n = excluded.n, counted_at = excluded.counted_at;
  end loop;
  return k;
end $$;
revoke execute on function public._section_count_check(uuid, text), public._section_counts_now(uuid) from public, anon, authenticated;

-- baseline: today's counts for every firm with rows (read from the live tables, nothing changed there)
insert into public.section_counts(firm_id, section, n)
select firm_id, section, count(*) from (
  select firm_id, section from firm_profile_facts where not hidden and section in ('overview', 'funds', 'lps')
  union all select firm_id, 'legal' from firm_legal_items where not hidden
  union all select firm_id, 'timeline' from timeline_events where not hidden
  union all select firm_id, 'people' from firm_people_roles where not hidden
  union all select firm_id, 'press' from press_item_firms where not hidden) x
group by 1, 2 on conflict do nothing;

CREATE OR REPLACE FUNCTION public.promote_enrichment(p_firm uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare lead_m boolean; e research_enrichments; it record; f firms; rid uuid; xid uuid; xv text; n int := 0; cnt jsonb;
  chk text := to_char(now() at time zone 'America/Los_Angeles', 'Mon FMDD, YYYY');
  t_t text; t_id uuid; t_c text; person text; v text; lbl text; tbl text; badge text; lead boolean;
begin
  select * into f from firms where id = p_firm;
  if f.id is null then return '{}'; end if;
  select * into e from research_enrichments where firm_id = p_firm and valid order by received_at desc, id desc limit 1;
  if e.id is null or e.id < _rules_cutoff() then return _promote_enrichment_legacy(p_firm); end if;
  delete from publish_checks where origin = 'enrichment' and origin_id = e.id and outcome in ('published', 'merged', 'conflict');
  insert into firm_owned_media(firm_id, host, path, label, origin)
  select p_firm, _dom(u), coalesce(rtrim(substring(lower(u) from '://[^/]+(/[^?#]*)'), '/'), ''), nullif(o->>'label', ''), 'enricher'
    from jsonb_array_elements(case when jsonb_typeof(e.payload->'owned_media') = 'array' then e.payload->'owned_media' else '[]' end) o,
         lateral (select case jsonb_typeof(o) when 'string' then o #>> '{}' else coalesce(o->>'url', o->>'source') end u) z
   where _dom(u) is not null
  on conflict do nothing;

  for it in select * from checked_items(e.payload) c where c.outcome = 'ok' order by c.n loop
    rid := md5('enrich:' || p_firm || ':' || it.kind || ':' || it.section || ':' || coalesce(it.field, '') || ':' || it.f::text || ':' || it.url)::uuid;
    if _is_locked_any(rid, p_firm) then
      perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'rejected', 'removed or locked by a cleanup: not re-added', null, rid); continue;
    end if;
    xv := _removed_match(p_firm, it.section, concat_ws(' ', it.f->>'title', it.f->>'value', it.f->>'event', it.f->>'name', it.f->>'role', it.f->>'company', it.f->>'headline', it.f->>'snippet'), array[it.url]);
    if xv is not null then
      perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'rejected', xv, 'removed_items', null); continue;
    end if;
    lead := it.kind = 'lead';
    badge := case it.kind when 'fix' then 'Correction' when 'lead' then 'Lead (unverified)' end;
    xid := null; xv := null;

    if it.kind = 'fix' then
      t_t := null; t_id := null; t_c := null;
      person := coalesce(it.f->>'person', it.f->>'name');
      v := coalesce(it.f->>'value', it.f->>'role');
      if it.section = 'people' and person is not null then
        select 'firm_people_roles', id, 'role' into t_t, t_id, t_c from firm_people_roles
         where firm_id = p_firm and not hidden and _norm_txt(person_name) = _norm_txt(person) order by sort_order limit 1;
      elsif lower(it.field) ~ '^(aum|facts\.aum)' then
        select 'firm_profile_facts', id, 'value' into t_t, t_id, t_c from firm_profile_facts
         where firm_id = p_firm and hero_label in ('Assets', 'Regulatory AUM', 'AUM') order by origin nulls first limit 1;
      elsif lower(it.field) = 'hq' then
        select 'firm_profile_facts', id, 'value' into t_t, t_id, t_c from firm_profile_facts
         where firm_id = p_firm and hero_label = 'HQ' order by origin nulls first limit 1;
      end if;
      if t_id is not null and _is_locked(t_t, t_id, p_firm) then
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'conflict', 'row is locked by a cleanup: correction not applied', t_t, t_id); continue;
      end if;
      insert into firm_corrections(id, firm_id, registry_id, enrichment_id, field, record_id, bot_value, correct_value, source_url, target_table, target_id, target_col)
      values (rid, p_firm, e.registry_id, e.id, it.field, it.item->>'record_id', it.item->>'bot_value', left(v, 1000), it.url, t_t, t_id, t_c)
      on conflict (id) do update set active = true, enrichment_id = excluded.enrichment_id, target_table = excluded.target_table,
        target_id = excluded.target_id, target_col = excluded.target_col;
      perform _enrich_cite(p_firm, 'firm_corrections', rid, it.url, chk);
      insert into enrichment_rows values (p_firm, 'firm_corrections', rid, e.id) on conflict do nothing;
      if t_id is not null then
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'published', 'correction shown over the existing row (row itself unchanged)', t_t, t_id); n := n + 1; continue;
      end if;
      if it.section = 'people' then
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'rejected', 'fix names a person who is not on the page: send them as "add" with {name, role, source}', null, null); continue;
      end if;
    end if;

    if it.section = 'people' then
      v := (it.f->>'role') || coalesce(', ' || (it.f->>'company'), '') || coalesce(' (since ' || (it.f->>'since') || ')', '');
      select id, role into xid, xv from firm_people_roles
       where firm_id = p_firm and not hidden and kind = it.f->>'kind' and stable_key = _person_key(it.f->>'name')
       order by _norm_txt(role) = _norm_txt(v) desc, sort_order limit 1;
      if xid is not null and (_norm_txt(xv) = _norm_txt(v) or coalesce(xv, '') = '' or position(_norm_txt(it.f->>'role') in _norm_txt(xv)) > 0) then
        if not _is_locked('firm_people_roles', xid, p_firm) then perform _enrich_cite_merge(p_firm, 'firm_people_roles', xid, it.url, chk, e.id); end if;
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'merged', 'already on the page: source added', 'firm_people_roles', xid);
      elsif xid is not null and it.f->>'kind' = 'officer' then
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'conflict', format('page lists %s as "%s"; bot says "%s" (not overwritten; send a fix with a source if the page is wrong)', it.f->>'name', xv, v), 'firm_people_roles', xid);
      else
        insert into firm_people_roles(id, firm_id, kind, person_name, role, badge, sort_order)
        values (rid, p_firm, it.f->>'kind', left(it.f->>'name', 120), left(v, 300), badge, 500 + it.n) on conflict (id) do nothing;
        perform _enrich_cite(p_firm, 'firm_people_roles', rid, it.url, chk);
        insert into enrichment_rows values (p_firm, 'firm_people_roles', rid, e.id) on conflict do nothing;
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'published', null, 'firm_people_roles', rid);
      end if;

    elsif it.section in ('overview', 'funds', 'lps') then
      if it.section = 'funds' and not coalesce((it.f->>'scalar')::boolean, false) then
        v := concat_ws(' · ', it.f->>'name',
               case when it.f ? 'amount' then case when it.f->>'currency' = 'USD' then _promo_money(jsonb_build_object('amount_usd', (it.f->>'amount')::numeric))
                                                   else (it.f->>'amount') || ' ' || (it.f->>'currency') end end,
               it.f->>'date');
        lbl := 'Funds';
        select id, value into xid, xv from firm_profile_facts
         where firm_id = p_firm and section = 'funds' and (_norm_txt(value) = _norm_txt(v) or _norm_txt(split_part(value, ' · ', 1)) = _norm_txt(it.f->>'name') or stable_key = _fund_key(v))
         order by _norm_txt(value) = _norm_txt(v) desc limit 1;
      elsif it.section = 'lps' then
        v := (it.f->>'name') || coalesce(' (' || (it.f->>'type') || ')', ''); lbl := 'Limited partners';
        select id, value into xid, xv from firm_profile_facts
         where firm_id = p_firm and section = 'lps' and _norm_txt(split_part(value, ' (', 1)) = _norm_txt(it.f->>'name') limit 1;
      else
        v := it.f->>'value'; lbl := it.f->>'label';
        select id, value into xid, xv from firm_profile_facts
         where firm_id = p_firm and section = it.section and (_norm_txt(value) = _norm_txt(v)
               or (_norm_txt(coalesce(label, hero_label)) = _norm_txt(lbl) and lbl in ('Headquarters', 'Founded', 'Regulatory AUM')))
         order by _norm_txt(value) = _norm_txt(v) desc limit 1;
      end if;
      if lead then lbl := 'Lead (unverified)'; elsif it.kind = 'fix' then lbl := 'Correction'; end if;
      if xid is not null and (_norm_txt(xv) = _norm_txt(v) or (it.section = 'funds' and _fund_key(xv) = _fund_key(v)
          and _norm_txt(substring(xv from ' · (.*)$')) = _norm_txt(substring(v from ' · (.*)$')))) then
        if not _is_locked('firm_profile_facts', xid, p_firm) then perform _enrich_cite_merge(p_firm, 'firm_profile_facts', xid, it.url, chk, e.id); end if;
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'merged', 'already on the page: source added', 'firm_profile_facts', xid);
      elsif xid is not null and not lead and it.kind <> 'fix' then
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'conflict', format('page says "%s"; bot says "%s" (not overwritten; send a fix with a source if the page is wrong)', xv, v), 'firm_profile_facts', xid);
      else
        insert into firm_profile_facts(id, firm_id, section, label, value, sort_order, origin)
        values (rid, p_firm, it.section, lbl, left(v, 400), 500 + it.n, 'enricher submission ' || e.id) on conflict (id) do nothing;
        perform _enrich_cite(p_firm, 'firm_profile_facts', rid, it.url, chk);
        insert into enrichment_rows values (p_firm, 'firm_profile_facts', rid, e.id) on conflict do nothing;
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'published', null, 'firm_profile_facts', rid);
      end if;

    elsif it.section = 'legal' then
      lead := lead or coalesce((it.f->>'allegation')::boolean, false);
      v := case when lead then 'Lead (allegation, not verified): ' || (it.f->>'title') when it.kind = 'fix' then 'Correction: ' || (it.f->>'title') else it.f->>'title' end;
      select id into xid from firm_legal_items where firm_id = p_firm and (stable_key = _legal_key(it.f->>'title') or _norm_txt(regexp_replace(title, '^(Lead \(allegation, not verified\)|Correction): ', '')) = _norm_txt(it.f->>'title')) order by stable_key = _legal_key(it.f->>'title') desc limit 1;
      if xid is not null then
        if not _is_locked('firm_legal_items', xid, p_firm) then perform _enrich_cite_merge(p_firm, 'firm_legal_items', xid, it.url, chk, e.id); end if;
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'merged', 'already on the page: source added', 'firm_legal_items', xid);
      else
        insert into firm_legal_items(id, firm_id, grp, title, year_label, state, status_label, tone, note, sort_order)
        values (rid, p_firm,
          case when _dom(it.url) ~ '(courtlistener\.com|uscourts\.gov|pacer\.gov|justia\.com|law360\.com|casetext\.com)$' then 'case'
               when _dom(it.url) ~ '(sec\.gov|finra\.org|fca\.org\.uk)$' then 'regulator' else 'context' end,
          left(v, 300), coalesce(substring(it.f->>'date' from '^(\d{4})'), substring(it.f->>'title' from '((19|20)\d{2})')),
          case when lead then 'Unverified' when coalesce(it.f->>'status', it.f->>'title') ~* '(dismissed|terminated|settled|closed|judgment|vacated)' then 'Closed' end,
          case when lead then 'Lead · allegation' else it.f->>'status' end, null, null, 500 + it.n) on conflict (id) do nothing;
        perform _enrich_cite(p_firm, 'firm_legal_items', rid, it.url, chk);
        insert into enrichment_rows values (p_firm, 'firm_legal_items', rid, e.id) on conflict do nothing;
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'published', null, 'firm_legal_items', rid);
      end if;

    elsif it.section = 'timeline' then
      select id into xid from timeline_events where firm_id = p_firm and ((date_label = it.f->>'date' and _norm_txt(body) = _norm_txt(it.f->>'event')) or stable_key = _timeline_key(it.f->>'date', it.f->>'event')) limit 1;
      if xid is not null then
        if not _is_locked('timeline_events', xid, p_firm) then perform _enrich_cite_merge(p_firm, 'timeline_events', xid, it.url, chk, e.id); end if;
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'merged', 'already on the page: source added', 'timeline_events', xid);
      else
        insert into timeline_events(id, firm_id, date_label, kind, body, sort_order)
        values (rid, p_firm, it.f->>'date', case when lead then 'Lead (unverified)' else 'Reported' end, left(it.f->>'event', 300),
          500 - coalesce(substring(it.f->>'date' from '^(\d{4})')::int - 1900, 0)) on conflict (id) do nothing;
        perform _enrich_cite(p_firm, 'timeline_events', rid, it.url, chk);
        insert into enrichment_rows values (p_firm, 'timeline_events', rid, e.id) on conflict do nothing;
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'published', null, 'timeline_events', rid);
      end if;

    elsif it.section = 'founders' then
      -- founder quotes go to reviews (Activity): one review per source url, sources merged; nothing new in founder_accounts
      select r.rid, r.merged into xid, lead_m from _founder_review(p_firm, it.f->>'who', it.f->>'quote', it.url, it.f->>'date', it.f->>'outlet') r;
      perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item,
        case when lead_m then 'merged' else 'published' end, case when lead_m then 'already in reviews' end, 'reviews', xid);

    elsif it.section = 'press' then
      select id into rid from press_items where url = it.url order by created_at limit 1;
      if rid is null then
        rid := md5('enrich-press:' || it.url)::uuid;
        insert into press_items(id, publisher, domain, url, published_on, published_label, headline, snippet, data_status, retrieved_at, source_system)
        values (rid, coalesce(it.f->>'outlet', source_label(_dom(it.url), it.url)), _dom(it.url), it.url,
          case when it.f->>'date' ~ '^\d{4}-\d{2}-\d{2}$' then (it.f->>'date')::date end, it.f->>'date',
          left(it.f->>'headline', 400), left(it.f->>'snippet', 600), 'real', now(), 'enricher') on conflict (id) do nothing;
      end if;
      if _is_locked('press_item_firms', rid, p_firm) then
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'rejected', 'removed or locked by a cleanup: not re-added', 'press_items', rid);
      elsif exists (select 1 from press_item_firms where press_item_id = rid and firm_id = p_firm) then
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'merged', 'already on the page', 'press_items', rid);
      else
        insert into press_item_firms(press_item_id, firm_id, sort_order) values (rid, p_firm, 500 + it.n);
        insert into enrichment_rows values (p_firm, 'press_item_firms', rid, e.id) on conflict do nothing;
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'published', null, 'press_items', rid);
      end if;
    else
      continue;
    end if;
    n := n + 1;
  end loop;
  select coalesce(jsonb_object_agg(table_name, c), '{}') into cnt from (select table_name, count(*) c from enrichment_rows where firm_id = p_firm group by 1) x;
  perform _apply_name_only(p_firm);
  perform _section_count_check(p_firm, 'promote_enrichment ' || e.id);
  return cnt || jsonb_build_object('promoted', n, 'enrichment_id', e.id, 'rule', 'data-rules');
end $function$;

CREATE OR REPLACE FUNCTION public._promote_enrichment_legacy(p_firm uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare e research_enrichments; it record; rid uuid; n int := 0; i int := 0; f firms; dom text; handle text; t_t text; t_id uuid; t_c text;
  person text; chk text := to_char(now() at time zone 'America/Los_Angeles', 'Mon FMDD, YYYY'); cnt jsonb := '{}';
begin
  select * into f from firms where id = p_firm;
  if f.id is null then return '{}'; end if;
  select * into e from research_enrichments where firm_id = p_firm and valid order by received_at desc, id desc limit 1;
  if e.id is null then
    perform _apply_name_only(p_firm);
    return '{}';
  end if;
  insert into firm_owned_media(firm_id, host, path, label, origin)
  select p_firm, _dom(u), coalesce(rtrim(substring(lower(u) from '://[^/]+(/[^?#]*)'), '/'), ''), nullif(o->>'label', ''), 'enricher'
    from jsonb_array_elements(case when jsonb_typeof(e.payload->'owned_media') = 'array' then e.payload->'owned_media' else '[]' end) o,
         lateral (select case jsonb_typeof(o) when 'string' then o #>> '{}' else coalesce(o->>'url', o->>'source') end u) z
   where _dom(u) is not null
  on conflict do nothing;
  dom := coalesce(nullif(f.primary_domain, ''), '~none~');
  handle := lower(regexp_replace(coalesce(nullif(f.short_name, ''), f.name), '[^A-Za-z0-9]', '', 'g'));
  for it in select * from enrichment_items(e.payload) where ok loop
    i := i + 1;
    rid := md5('enrich:' || p_firm || ':' || it.kind || ':' || it.section || ':' || coalesce(it.field, '') || ':' || it.txt || ':' || it.url)::uuid;
    continue when _is_locked_any(rid, p_firm);  -- removed or locked by a cleanup: never re-add or touch
    person := _removed_match(p_firm, it.section, it.txt, array[it.url]);
    if person is not null then
      perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, to_jsonb(it), 'rejected', person, 'removed_items', null); continue;
    end if;
    person := _data_rule(it.section, it.kind, case it.section
        when 'people' then jsonb_build_object('name', it.txt) when 'legal' then jsonb_build_object('title', it.txt)
        when 'timeline' then jsonb_build_object('event', it.txt, 'date', it.date_label)
        when 'press' then jsonb_build_object('headline', it.txt, 'date', it.date_label)
        when 'founders' then '{}'::jsonb else jsonb_build_object('value', it.txt) end, it.url);
    if person is not null then
      perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, to_jsonb(it), 'rejected', person, null, null); continue;
    end if;
    if it.kind = 'fix' then
      t_t := null; t_id := null; t_c := null; person := substring(it.field from '\[([^\]]+)\]');
      if it.section = 'people' and person is not null then
        select 'firm_people_roles' t, id, 'role' c into t_t, t_id, t_c from firm_people_roles
         where firm_id = p_firm and person_name ilike '%' || person || '%'
         order by person_name ilike person || '%' desc, id in (select row_id from enrichment_rows where firm_id = p_firm), sort_order limit 1;
      elsif lower(it.field) ~ '^(aum|facts\.aum)' then
        select 'firm_profile_facts' t, id, 'value' c into t_t, t_id, t_c from firm_profile_facts
         where firm_id = p_firm and hero_label in ('Assets', 'Regulatory AUM', 'AUM') order by origin nulls first limit 1;
      elsif lower(it.field) = 'hq' then
        select 'firm_profile_facts' t, id, 'value' c into t_t, t_id, t_c from firm_profile_facts
         where firm_id = p_firm and hero_label = 'HQ' order by origin nulls first limit 1;
      end if;
      continue when t_id is not null and _is_locked(t_t, t_id, p_firm);  -- never correct over a locked row
      insert into firm_corrections(id, firm_id, registry_id, enrichment_id, field, record_id, bot_value, correct_value, source_url, target_table, target_id, target_col)
      values (rid, p_firm, e.registry_id, e.id, it.field, it.record_id, it.bot_value, left(it.txt, 1000), it.url, t_t, t_id, t_c)
      on conflict (id) do update set active = true, enrichment_id = excluded.enrichment_id, target_table = excluded.target_table,
        target_id = excluded.target_id, target_col = excluded.target_col;
      perform _enrich_cite(p_firm, 'firm_corrections', rid, it.url, chk);
      insert into enrichment_rows values (p_firm, 'firm_corrections', rid, e.id) on conflict do nothing;
      if t_id is not null then n := n + 1; continue; end if;
    end if;
    if it.section in ('overview', 'funds', 'lps') then
      continue when exists (select 1 from firm_profile_facts x where x.firm_id = p_firm and x.id <> rid and (_norm_txt(x.value) = _norm_txt(left(it.txt, 600)) or (it.section = 'funds' and x.stable_key = _fund_key(left(it.txt, 400)))));
      insert into firm_profile_facts(id, firm_id, section, label, value, sort_order, origin)
      values (rid, p_firm, it.section,
        case it.kind when 'fix' then 'Correction' when 'lead' then 'Lead (unverified)'
          else case it.section when 'overview' then 'Overview' when 'funds' then 'Funds' else 'Limited partners' end end,
        left(it.txt, 600), 500 + i, 'enricher submission ' || e.id) on conflict (id) do nothing;
      perform _enrich_cite(p_firm, 'firm_profile_facts', rid, it.url, chk);
      insert into enrichment_rows values (p_firm, 'firm_profile_facts', rid, e.id) on conflict do nothing;
    elsif it.section = 'legal' then
      continue when exists (select 1 from firm_legal_items x where x.firm_id = p_firm and x.id <> rid and (strpos(_norm_txt(x.title), _norm_txt(left(it.txt, 600))) > 0 or x.stable_key = _legal_key(left(it.txt, 300))));
      insert into firm_legal_items(id, firm_id, grp, title, year_label, state, status_label, tone, note, sort_order)
      values (rid, p_firm,
        case when _dom(it.url) ~ '(courtlistener\.com|uscourts\.gov|pacer\.gov|justia\.com|law360\.com|casetext\.com)$' then 'case'
             when _dom(it.url) ~ '(sec\.gov|finra\.org|fca\.org\.uk)$' then 'regulator' else 'context' end,
        left(case when it.kind = 'lead' or it.txt ~* '^\s*lead\b' or it.txt ~* '\m(alleg|claim(s|ed)? that)' then
               case when it.txt ~* '^\s*lead\b' then it.txt else 'Lead (allegation, not verified): ' || it.txt end
             when it.kind = 'fix' then 'Correction: ' || it.txt else it.txt end, 600),
        substring(coalesce(it.date_label, it.txt) from '((19|20)\d{2})'),
        case when it.kind = 'lead' or it.txt ~* '^\s*lead\b' or it.txt ~* '\malleg' then 'Unverified'
             when it.txt ~* '(dismissed|terminated|settled|closed|judgment|vacated)' then 'Closed' end,
        case when it.kind = 'lead' or it.txt ~* '^\s*lead\b' or it.txt ~* '\malleg' then 'Lead · allegation' end,
        null, null, 500 + i) on conflict (id) do nothing;
      perform _enrich_cite(p_firm, 'firm_legal_items', rid, it.url, chk);
      insert into enrichment_rows values (p_firm, 'firm_legal_items', rid, e.id) on conflict do nothing;
    elsif it.section = 'people' then
      continue when exists (select 1 from firm_people_roles x where x.firm_id = p_firm and x.id <> rid and x.stable_key = _person_key(left(it.txt, 600)));
      insert into firm_people_roles(id, firm_id, kind, person_name, role, badge, sort_order)
      values (rid, p_firm,
        case when it.txt ~* '\m(board|director)' then 'board' when it.txt ~* '\m(left|joined|former|depart|hired|promoted)' then 'move' else 'officer' end,
        left(it.txt, 600), '', case it.kind when 'fix' then 'Correction' when 'lead' then 'Lead (unverified)' end, 500 + i) on conflict (id) do nothing;
      perform _enrich_cite(p_firm, 'firm_people_roles', rid, it.url, chk);
      insert into enrichment_rows values (p_firm, 'firm_people_roles', rid, e.id) on conflict do nothing;
    elsif it.section = 'timeline' then
      continue when exists (select 1 from timeline_events x where x.firm_id = p_firm and x.id <> rid and (_norm_txt(x.body) = _norm_txt(left(it.txt, 600)) or x.stable_key = _timeline_key(coalesce(nullif(it.date_label, ''), 'Undated'), left(it.txt, 600))));
      insert into timeline_events(id, firm_id, date_label, kind, body, sort_order)
      values (rid, p_firm, coalesce(nullif(it.date_label, ''), 'Undated'), 'Reported', left(it.txt, 600),
        500 - coalesce(substring(it.date_label from '^(\d{4})')::int - 1900, 0)) on conflict (id) do nothing;
      perform _enrich_cite(p_firm, 'timeline_events', rid, it.url, chk);
      insert into enrichment_rows values (p_firm, 'timeline_events', rid, e.id) on conflict do nothing;
    elsif it.section = 'founders' then
      -- founder quotes go to reviews (Activity), not the old founders section
      perform _founder_review(p_firm, it.who, it.txt, it.url, it.date_label, it.outlet);
    elsif it.section = 'press' then
      select id into rid from press_items where url = it.url order by created_at limit 1;
      if rid is null then
        rid := md5('enrich-press:' || it.url)::uuid;
        insert into press_items(id, publisher, domain, url, published_on, published_label, headline, snippet, data_status, retrieved_at, source_system)
        values (rid, coalesce(nullif(it.outlet, ''), source_label(_dom(it.url), it.url)), _dom(it.url), it.url,
          case when it.date_label ~ '^\d{4}-\d{2}-\d{2}$' then it.date_label::date end, it.date_label,
          left(it.txt, 400), left(it.who, 600), 'real', now(), 'enricher') on conflict (id) do nothing;
      end if;
      if not exists (select 1 from press_item_firms where press_item_id = rid and firm_id = p_firm) and not _is_locked('press_item_firms', rid, p_firm) then
        insert into press_item_firms(press_item_id, firm_id, sort_order) values (rid, p_firm, 500 + i);
        insert into enrichment_rows values (p_firm, 'press_item_firms', rid, e.id) on conflict do nothing;
      end if;
    else
      continue;
    end if;
    n := n + 1;
  end loop;
  select coalesce(jsonb_object_agg(table_name, c), '{}') into cnt from (select table_name, count(*) c from enrichment_rows where firm_id = p_firm group by 1) x;
  perform _apply_name_only(p_firm);
  perform _section_count_check(p_firm, 'promote_enrichment(legacy) ' || e.id);
  return cnt || jsonb_build_object('promoted', n, 'enrichment_id', e.id);
end $function$;

CREATE OR REPLACE FUNCTION public.promote_bot_facts(p_firm uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare qid text := _firm_queue_id(p_firm); k record; rec record; fid uuid; n int := 0;
  hv text; v text; xr text; hl text; src jsonb; sid uuid; i int;
begin
  if qid is null then return 0; end if;
  delete from publish_checks where origin = 'submission' and firm_id = p_firm and field in ('hq', 'aum');
  for k in select * from (values ('hq', 'overview', 'Headquarters', 'HQ', array['HQ'], 0),
                                 ('aum', 'funds', 'Assets under management', 'Assets', array['Assets', 'Regulatory AUM', 'AUM'], 0)) t(fp, sec, lbl, hl, same, so) loop
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
