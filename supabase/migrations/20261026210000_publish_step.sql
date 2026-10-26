-- Publish step (approval pt1607u).
--  * Nothing publishes on insert any more: research_enrichments and research_submissions both wait in the holding area.
--    The old auto_promote_enrichment switch only works in a test database (app.test_auto_publish = '1'); on prod it does nothing.
--  * Publishing happens only through a batch: create_publish_batch -> dry_run_publish_batch -> approve_publish_batch (Alex)
--    -> run_publish_batch. Manual only (no cron). Every added row and every check carries the batch id.
--  * Per-firm page check: a firm goes live only if no section disappears, no new stable_key collisions, no more rule
--    violations, and every section-count jump is explained by what the batch added. Otherwise the firm is held for Alex.
--  * Item-by-item merge across all of a firm's waiting enrichments, newest first: newer item wins, older item adds its source.
--  * Leads, allegations and fixes are held, never published (the old unverified-lead publishing code is removed).
--  * Old-format (pre-cutoff) enrichments go through the same rules; a row with nothing readable is held, never dropped.
--  * Undo hides the added rows and removes the added source links (kept in cleanup_backup); restores changed rows. No row deletes.
--  * publish_checks history is kept (no deletes on re-run).

alter table public.enrichment_rows add column if not exists batch_id text default nullif(current_setting('app.publish_batch', true), '');
alter table public.publish_checks add column if not exists batch_id text default nullif(current_setting('app.publish_batch', true), '');
alter table public.publish_checks drop constraint if exists publish_checks_outcome_check;
alter table public.publish_checks add constraint publish_checks_outcome_check
  check (outcome in ('published', 'merged', 'conflict', 'rejected', 'note', 'held'));
create index if not exists enrichment_rows_batch_idx on public.enrichment_rows(batch_id) where batch_id is not null;
create index if not exists publish_checks_batch_idx on public.publish_checks(batch_id, firm_id) where batch_id is not null;

create table if not exists public.publish_batches (
  id text primary key,
  source text not null check (source in ('enricher', 'submissions')),
  status text not null default 'draft' check (status in ('draft', 'approved', 'published', 'undone')),
  bot_like text,
  firm_ids uuid[] not null default '{}',
  created_at timestamptz not null default now(),
  dry_run_at timestamptz, dry_report jsonb,
  approved_by text, approved_at timestamptz,
  published_at timestamptz, run_report jsonb,
  undone_at timestamptz, undo_report jsonb);
create table if not exists public.publish_batch_firms (
  id bigserial primary key,
  batch_id text not null references public.publish_batches(id),
  firm_id uuid not null,
  phase text not null check (phase in ('dry', 'run')),
  decision text not null check (decision in ('live', 'held')),
  reasons text[] not null default '{}',
  items jsonb,
  created_at timestamptz not null default now());
create index if not exists publish_batch_firms_idx on public.publish_batch_firms(batch_id, phase);
alter table public.publish_batches enable row level security;
alter table public.publish_batch_firms enable row level security;
revoke all on public.publish_batches, public.publish_batch_firms from anon, authenticated;

-- auto-publish on insert: off everywhere except a test database
create or replace function public._auto_publish_on() returns boolean language sql stable set search_path = public as $$
  select coalesce((select value from ingest_settings where key = 'auto_promote_enrichment'), '0') = '1'
     and coalesce(current_setting('app.test_auto_publish', true), '') = '1' $$;

create or replace function public._enrichment_after_insert() returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  if new.valid then
    if new.firm_id is not null and _auto_publish_on() then perform promote_enrichment(new.firm_id); end if;
    perform search_log_from_enrichment(new.id);
    perform refresh_feedback_patterns();
  end if;
  return null;
end $fn$;

create or replace function public.promote_bot_facts_trg() returns trigger language plpgsql security definer set search_path = public as $fn$
declare f uuid;
begin
  if not new.valid then return null; end if;
  if not _auto_publish_on() then return null; end if;  -- waits for a publish batch
  for f in select id from firms where deleted_at is null and registry_id = _registry_target(new.registry_id) loop
    begin
      perform promote_bot_facts(f);
    exception when others then
      raise warning 'promote_bot_facts: submission % firm %: %', new.id, f, sqlerrm;
    end;
  end loop;
  return null;
end $fn$;

create or replace function public.checks_from_upload_trg() returns trigger language plpgsql security definer set search_path = public as $fn$
declare f uuid;
begin
  if not new.valid then return null; end if;
  if not _auto_publish_on() then return null; end if;  -- check results wait for a publish batch too
  for f in select id from firms where deleted_at is null and registry_id = _registry_target(new.registry_id) loop
    begin
      perform apply_checks_for_firm(f);
    exception when others then
      raise warning 'checks_from_upload: submission % firm %: %', new.id, f, sqlerrm;
    end;
  end loop;
  return null;
end $fn$;

-- back up a review a founder quote is about to merge into (so undo can put its sources back)
create or replace function public._backup_review_match(p_firm uuid, p_quote text, p_url text) returns void
language plpgsql security definer set search_path = public as $fn$
declare k text := case when coalesce(p_url, '') ~ '^https?://' then 'url:' || lower(regexp_replace(p_url, '^https?://(www\.)?|/+$', '', 'g'))
                       else 'quote:' || md5(_norm_txt(p_quote)) end;
begin
  insert into cleanup_backup(batch, firm_id, table_name, row_id, row_data)
  select 'publish:' || coalesce(nullif(current_setting('app.publish_batch', true), ''), 'none'), p_firm, 'reviews', r.id, to_jsonb(r)
    from reviews r where r.firm_id = p_firm
     and (r.dedupe_key = k or (coalesce(p_url, '') ~ '^https?://' and p_url = any(r.source_urls)) or (_norm_txt(r.body) = _norm_txt(p_quote) and coalesce(p_quote, '') <> ''))
   order by r.created_at limit 1;
end $fn$;

-- one enrichment row, item by item (called newest first for all of a firm's waiting rows)
create or replace function public._promote_one(p_firm uuid, e public.research_enrichments) returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare lead_m boolean; it record; rid uuid; xid uuid; xv text; n int := 0; h int := 0; k int := 0;
  chk text := to_char(now() at time zone 'America/Los_Angeles', 'Mon FMDD, YYYY');
  v text; lbl text;
begin
  insert into firm_owned_media(firm_id, host, path, label, origin)
  select p_firm, _dom(u), coalesce(rtrim(substring(lower(u) from '://[^/]+(/[^?#]*)'), '/'), ''), nullif(o->>'label', ''), 'enricher'
    from jsonb_array_elements(case when jsonb_typeof(e.payload->'owned_media') = 'array' then e.payload->'owned_media' else '[]' end) o,
         lateral (select case jsonb_typeof(o) when 'string' then o #>> '{}' else coalesce(o->>'url', o->>'source') end u) z
   where _dom(u) is not null
  on conflict do nothing;
  select count(*) into k from checked_items(e.payload);
  if k = 0 then
    perform _pc(e.id, e.bot_id, p_firm, 'all', 'row', null, null, 'held',
      case when e.id < _rules_cutoff() then 'old format: no readable items (held for a person, not dropped)' else 'no readable items (held for a person)' end, null, null);
    return jsonb_build_object('enrichment_id', e.id, 'published', 0, 'held_row', true);
  end if;
  -- old-format rows were never checked at upload: log their rejected items now (nothing dropped silently)
  if e.id < _rules_cutoff() then
    insert into publish_checks(origin, origin_id, bot_id, firm_id, section, kind, field, item, outcome, reason)
    select 'enrichment', e.id, e.bot_id, p_firm, c.section, c.kind, c.field, c.item, c.outcome, 'old format: ' || c.reason
      from checked_items(e.payload) c where c.outcome in ('rejected', 'note');
  end if;

  for it in select * from checked_items(e.payload) c where c.outcome = 'ok' order by c.n loop
    rid := md5('enrich:' || p_firm || ':' || it.kind || ':' || it.section || ':' || coalesce(it.field, '') || ':' || it.f::text || ':' || it.url)::uuid;
    if _is_locked_any(rid, p_firm) then
      perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'rejected', 'removed or locked by a cleanup: not re-added', null, rid); continue;
    end if;
    xv := _removed_match(p_firm, it.section, concat_ws(' ', it.f->>'title', it.f->>'value', it.f->>'event', it.f->>'name', it.f->>'role', it.f->>'company', it.f->>'headline', it.f->>'snippet'), array[it.url]);
    if xv is not null then
      perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'rejected', xv, 'removed_items', null); continue;
    end if;
    -- leads, allegations and fixes are never published by a bot: they wait for a person
    if it.kind in ('lead', 'fix') or (it.section = 'legal' and coalesce((it.f->>'allegation')::boolean, false)) then
      perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'held',
        case it.kind when 'fix' then 'fix (correction): held for a person to review' else 'lead or allegation: held for a person to review, never published by a bot' end, null, null);
      h := h + 1; continue;
    end if;
    xid := null; xv := null;

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
        values (rid, p_firm, it.f->>'kind', left(it.f->>'name', 120), left(v, 300), null, 500 + it.n) on conflict (id) do nothing;
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
      if xid is not null and (_norm_txt(xv) = _norm_txt(v) or (it.section = 'funds' and _fund_key(xv) = _fund_key(v)
          and _norm_txt(substring(xv from ' · (.*)$')) = _norm_txt(substring(v from ' · (.*)$')))) then
        if not _is_locked('firm_profile_facts', xid, p_firm) then perform _enrich_cite_merge(p_firm, 'firm_profile_facts', xid, it.url, chk, e.id); end if;
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'merged', 'already on the page: source added', 'firm_profile_facts', xid);
      elsif xid is not null then
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'conflict', format('page says "%s"; bot says "%s" (not overwritten; send a fix with a source if the page is wrong)', xv, v), 'firm_profile_facts', xid);
      else
        insert into firm_profile_facts(id, firm_id, section, label, value, sort_order, origin)
        values (rid, p_firm, it.section, lbl, left(v, 400), 500 + it.n, 'enricher submission ' || e.id) on conflict (id) do nothing;
        perform _enrich_cite(p_firm, 'firm_profile_facts', rid, it.url, chk);
        insert into enrichment_rows values (p_firm, 'firm_profile_facts', rid, e.id) on conflict do nothing;
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'published', null, 'firm_profile_facts', rid);
      end if;

    elsif it.section = 'legal' then
      v := it.f->>'title';
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
          case when coalesce(it.f->>'status', it.f->>'title') ~* '(dismissed|terminated|settled|closed|judgment|vacated)' then 'Closed' end,
          it.f->>'status', null, null, 500 + it.n) on conflict (id) do nothing;
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
        values (rid, p_firm, it.f->>'date', 'Reported', left(it.f->>'event', 300),
          500 - coalesce(substring(it.f->>'date' from '^(\d{4})')::int - 1900, 0)) on conflict (id) do nothing;
        perform _enrich_cite(p_firm, 'timeline_events', rid, it.url, chk);
        insert into enrichment_rows values (p_firm, 'timeline_events', rid, e.id) on conflict do nothing;
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'published', null, 'timeline_events', rid);
      end if;

    elsif it.section = 'founders' then
      -- founder quotes go to reviews (Activity): one review per source url, sources merged; nothing new in founder_accounts
      perform _backup_review_match(p_firm, it.f->>'quote', it.url);
      select r.rid, r.merged into xid, lead_m from _founder_review(p_firm, it.f->>'who', it.f->>'quote', it.url, it.f->>'date', it.f->>'outlet') r;
      perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item,
        case when lead_m then 'merged' else 'published' end, case when lead_m then 'already in reviews' end, 'reviews', xid);
      if not lead_m then insert into enrichment_rows values (p_firm, 'reviews', xid, e.id) on conflict do nothing; end if;

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
  return jsonb_build_object('enrichment_id', e.id, 'published', n, 'held', h);
end $fn$;
revoke execute on function public._promote_one(uuid, public.research_enrichments) from public, anon, authenticated;

-- all of a firm's waiting enrichments (no published/merged/conflict/held check yet), newest first
create or replace function public._waiting_enrichments(p_firm uuid) returns setof public.research_enrichments
language sql stable set search_path = public as $$
  select e.* from research_enrichments e
   where e.firm_id = p_firm and e.valid
     and not exists (select 1 from publish_checks c where c.origin = 'enrichment' and c.origin_id = e.id and c.firm_id = e.firm_id
                      and (c.outcome in ('published', 'merged', 'conflict', 'held') or c.batch_id is not null))
   order by e.received_at desc, e.id desc $$;

create or replace function public.promote_enrichment(p_firm uuid) returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare e research_enrichments; r jsonb := '[]'; last_id bigint; cnt jsonb; n int := 0;
begin
  if not exists (select 1 from firms where id = p_firm) then return '{}'; end if;
  for e in select * from _waiting_enrichments(p_firm) loop
    r := r || _promote_one(p_firm, e);
    n := n + coalesce((r->-1->>'published')::int, 0);
    last_id := coalesce(last_id, e.id);
  end loop;
  select coalesce(jsonb_object_agg(table_name, c), '{}') into cnt from (select table_name, count(*) c from enrichment_rows where firm_id = p_firm group by 1) x;
  perform _apply_name_only(p_firm);
  perform _section_count_check(p_firm, 'promote_enrichment ' || coalesce(last_id::text, '-'));
  return cnt || jsonb_build_object('promoted', n, 'enrichment_id', last_id, 'rows', r, 'rule', 'data-rules');
end $fn$;
revoke execute on function public.promote_enrichment(uuid) from public, anon, authenticated;

-- submissions (friend's portal bots): hq/aum facts + the 10 check rows, with backups for undo
create or replace function public._promote_submissions(p_firm uuid) returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare b text := 'publish:' || coalesce(nullif(current_setting('app.publish_batch', true), ''), 'none');
  before jsonb; n int; c int := 0; sid bigint;
begin
  insert into cleanup_backup(batch, firm_id, table_name, row_id, row_data)
  select b, p_firm, 'firm_check_rows', null, to_jsonb(r) from firm_check_rows r where r.firm_id = p_firm;
  select coalesce(jsonb_object_agg(n::text, state), '{}') into before from firm_check_rows where firm_id = p_firm;
  n := promote_bot_facts(p_firm);
  sid := apply_checks_for_firm(p_firm);
  select count(*) into c from firm_check_rows r where r.firm_id = p_firm and r.state is distinct from (before->>(r.n::text));
  return jsonb_build_object('facts', n, 'check_rows_changed', c, 'submission_id', sid);
end $fn$;
revoke execute on function public._promote_submissions(uuid) from public, anon, authenticated;

create or replace function public._firm_rules_n(p_firm uuid) returns int language sql stable set search_path = public as $$
  select count(*)::int from data_rules_report() where firm_id = p_firm $$;
create or replace function public._firm_collisions_n(p_firm uuid) returns int language sql stable set search_path = public as $$
  select coalesce(sum(n), 0)::int from stable_key_collisions() where firm_id = p_firm $$;

-- publish one firm inside a batch and check its page; returns {decision, reasons, items}
create or replace function public._publish_firm(p_batch text, p_source text, p_firm uuid) returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare b0 jsonb; b1 jsonb; r0 int; r1 int; c0 int; c1 int; reasons text[] := '{}'; s record; added int; res jsonb;
  items jsonb; blocked jsonb; a0 bigint := coalesce((select max(id) from section_count_alerts), 0);
begin
  perform set_config('app.publish_batch', p_batch, true);
  select jsonb_object_agg(section, n) into b0 from _section_counts_now(p_firm);
  r0 := _firm_rules_n(p_firm); c0 := _firm_collisions_n(p_firm);
  if p_source = 'enricher' then res := promote_enrichment(p_firm); else res := _promote_submissions(p_firm); end if;
  select jsonb_object_agg(section, n) into b1 from _section_counts_now(p_firm);
  r1 := _firm_rules_n(p_firm); c1 := _firm_collisions_n(p_firm);
  for s in select key sec, (b0->>key)::int a, (b1->>key)::int z from jsonb_each(b0) loop
    if s.a > 0 and s.z = 0 then reasons := reasons || format('section %s went missing (%s -> 0)', s.sec, s.a);
    elsif s.z < s.a then reasons := reasons || format('section %s dropped (%s -> %s)', s.sec, s.a, s.z);
    end if;
  end loop;
  if c1 > c0 then reasons := reasons || format('new duplicates / stable_key collisions (%s -> %s)', c0, c1); end if;
  if r1 > r0 then reasons := reasons || format('more data-rule violations (%s -> %s)', r0, r1); end if;
  -- every section-count alert raised by this run must be explained by what the batch added in that section
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
end $fn$;
revoke execute on function public._publish_firm(text, text, uuid) from public, anon, authenticated;

-- firms with work waiting for a source (optionally only some bots: e.g. 'portal-night-bot%')
create or replace function public._waiting_firms(p_source text, p_bot_like text) returns uuid[]
language sql stable set search_path = public as $$
  select coalesce(array_agg(distinct f.id), '{}') from firms f
   where f.deleted_at is null and case when p_source = 'enricher' then
     exists (select 1 from _waiting_enrichments(f.id) e where p_bot_like is null or e.bot_id like p_bot_like)
   else exists (select 1 from research_submissions s where s.valid and s.registry_id = _firm_queue_id(f.id)
                  and (p_bot_like is null or s.bot_id like p_bot_like)) end $$;

create or replace function public.create_publish_batch(p_id text, p_source text, p_bot_like text default null, p_firms uuid[] default null)
returns jsonb language plpgsql security definer set search_path = public as $fn$
declare ids uuid[] := coalesce(p_firms, _waiting_firms(p_source, p_bot_like));
begin
  insert into publish_batches(id, source, bot_like, firm_ids) values (p_id, p_source, p_bot_like, ids);
  return jsonb_build_object('batch', p_id, 'source', p_source, 'firms', cardinality(ids));
end $fn$;

-- dry run: publish each firm and check it, then roll everything back. Keeps a per-firm record. p_from/p_limit for chunks.
create or replace function public.dry_run_publish_batch(p_id text, p_from int default 1, p_limit int default 100000)
returns jsonb language plpgsql security definer set search_path = public as $fn$
declare b publish_batches; f uuid; r jsonb; i int := 0;
begin
  select * into b from publish_batches where id = p_id;
  if b.id is null then raise exception 'no batch %', p_id; end if;
  if b.status <> 'draft' then raise exception 'batch % is %, dry runs only for draft batches', p_id, b.status; end if;
  if p_from = 1 then delete from publish_batch_firms where batch_id = p_id and phase = 'dry'; end if;  -- the batch's own scratch rows only
  foreach f in array b.firm_ids[p_from : p_from + p_limit - 1] loop
    begin
      r := _publish_firm(p_id, b.source, f);
      raise exception using errcode = 'P0001', message = 'dryrun-rollback';
    exception when others then
      if sqlerrm <> 'dryrun-rollback' then r := jsonb_build_object('decision', 'held', 'reasons', jsonb_build_array('error: ' || sqlerrm)); end if;
    end;
    insert into publish_batch_firms(batch_id, firm_id, phase, decision, reasons, items)
    values (p_id, f, 'dry', r->>'decision', array(select jsonb_array_elements_text(r->'reasons')), r - 'decision' - 'reasons');
    i := i + 1;
  end loop;
  update publish_batches set dry_run_at = now(), dry_report = publish_batch_summary(p_id, 'dry') where id = p_id;
  return jsonb_build_object('batch', p_id, 'firms_checked', i);
end $fn$;

create or replace function public.publish_batch_summary(p_id text, p_phase text default 'dry') returns jsonb
language sql stable set search_path = public as $$
  with x as (select * from publish_batch_firms where batch_id = p_id and phase = p_phase),
  it as (select x.decision, o.key outcome, s.key section, s.value::int n from x, jsonb_each(coalesce(x.items->'items', '{}')) o, jsonb_each_text(o.value) s)
  select jsonb_build_object(
    'firms', (select count(*) from x),
    'firms_live', (select count(*) from x where decision = 'live'),
    'firms_held', (select count(*) from x where decision = 'held'),
    'items_live_by_section', (select coalesce(jsonb_object_agg(section, n), '{}') from (select section, sum(n) n from it where decision = 'live' and outcome = 'published' group by 1) q),
    'items_by_outcome', (select coalesce(jsonb_object_agg(outcome, n), '{}') from (select outcome, sum(n) n from it group by 1) q),
    'alerts', (select coalesce(sum((items->>'alerts')::int), 0) from x),
    'held_reasons', (select coalesce(jsonb_object_agg(r, n), '{}') from (select regexp_replace(r, '\d+', '#', 'g') r, count(*) n from x, unnest(reasons) r group by 1) q)) $$;

-- only Alex approves. Not callable by the site or bots (service role / SQL editor only).
create or replace function public.approve_publish_batch(p_id text, p_approved_by text)
returns jsonb language plpgsql security definer set search_path = public as $fn$
begin
  if coalesce(btrim(p_approved_by), '') = '' then raise exception 'approver name required'; end if;
  update publish_batches set status = 'approved', approved_by = p_approved_by, approved_at = now()
   where id = p_id and status = 'draft' and dry_run_at is not null;
  if not found then raise exception 'batch % must be a draft with a dry run before approval', p_id; end if;
  return jsonb_build_object('batch', p_id, 'status', 'approved');
end $fn$;

-- the real run: each firm is published and checked; a firm that fails is rolled back and held.
create or replace function public.run_publish_batch(p_id text) returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare b publish_batches; f uuid; r jsonb;
begin
  select * into b from publish_batches where id = p_id for update;
  if b.status is distinct from 'approved' then raise exception 'batch % is not approved (status %)', p_id, b.status; end if;
  foreach f in array b.firm_ids loop
    begin
      r := _publish_firm(p_id, b.source, f);
      if r->>'decision' = 'held' then raise exception using errcode = 'P0001', message = 'held-rollback'; end if;
    exception when others then
      if sqlerrm <> 'held-rollback' then r := jsonb_build_object('decision', 'held', 'reasons', jsonb_build_array('error: ' || sqlerrm)); end if;
    end;
    insert into publish_batch_firms(batch_id, firm_id, phase, decision, reasons, items)
    values (p_id, f, 'run', r->>'decision', array(select jsonb_array_elements_text(r->'reasons')), r - 'decision' - 'reasons');
  end loop;
  update publish_batches set status = 'published', published_at = now(), run_report = publish_batch_summary(p_id, 'run') where id = p_id;
  return (select run_report from publish_batches where id = p_id);
end $fn$;

-- undo: hide what the batch added, remove the source links it added (copied to cleanup_backup first), restore changed rows
create or replace function public.undo_publish_batch(p_id text) returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare b publish_batches; r record; hid int := 0; src int := 0; rest int := 0; why text := 'undo of publish batch ' || p_id;
begin
  select * into b from publish_batches where id = p_id for update;
  if b.status is distinct from 'published' then raise exception 'batch % is not published (status %)', p_id, b.status; end if;
  for r in select * from enrichment_rows where batch_id = p_id loop
    if r.table_name in ('firm_profile_facts', 'firm_legal_items', 'timeline_events', 'firm_people_roles') then
      execute format('update %I set hidden = true, hidden_reason = $1, hidden_at = now(), hidden_by = $2 where id = $3 and firm_id = $4 and not hidden', r.table_name)
        using why, 'undo:' || p_id, r.row_id, r.firm_id;
      hid := hid + 1;
    elsif r.table_name = 'press_item_firms' then
      update press_item_firms set hidden = true, hidden_reason = why, hidden_at = now(), hidden_by = 'undo:' || p_id
       where press_item_id = r.row_id and firm_id = r.firm_id and not hidden;
      hid := hid + 1;
    elsif r.table_name = 'reviews' then
      insert into cleanup_backup(batch, firm_id, table_name, row_id, row_data) select 'undo:' || p_id, r.firm_id, 'reviews', x.id, to_jsonb(x) from reviews x where x.id = r.row_id;
      update reviews set is_public = false where id = r.row_id;
      hid := hid + 1;
    elsif r.table_name = 'fact_sources' then
      insert into cleanup_backup(batch, firm_id, table_name, row_id, row_data) select 'undo:' || p_id, r.firm_id, 'fact_sources', x.id, to_jsonb(x) from fact_sources x where x.id = r.row_id;
      delete from fact_sources where id = r.row_id;  -- the link only; the copy stays in cleanup_backup
      src := src + 1;
    end if;
  end loop;
  -- put back rows the batch changed (newest backup per row is the pre-batch state)
  for r in select distinct on (table_name, coalesce(row_id::text, (row_data->>'n')), firm_id) * from cleanup_backup
            where batch = 'publish:' || p_id order by table_name, coalesce(row_id::text, (row_data->>'n')), firm_id, id loop
    if r.table_name = 'firm_check_rows' then
      update firm_check_rows t set state = r.row_data->>'state', count_label = r.row_data->>'count_label',
        searched_at = (r.row_data->>'searched_at')::timestamptz, source_submission = (r.row_data->>'source_submission')::bigint
       where t.firm_id = r.firm_id and t.n = (r.row_data->>'n')::int;
    elsif r.table_name = 'firm_profile_facts' then
      update firm_profile_facts set value = r.row_data->>'value', hero_label = r.row_data->>'hero_label', hero_value = r.row_data->>'hero_value', origin = r.row_data->>'origin' where id = r.row_id;
    elsif r.table_name = 'reviews' then
      update reviews set source_urls = array(select jsonb_array_elements_text(r.row_data->'source_urls')) where id = r.row_id;
    end if;
    rest := rest + 1;
  end loop;
  update publish_batches set status = 'undone', undone_at = now(),
    undo_report = jsonb_build_object('hidden', hid, 'sources_removed', src, 'restored', rest) where id = p_id;
  return jsonb_build_object('batch', p_id, 'hidden', hid, 'sources_removed', src, 'restored', rest);
end $fn$;

revoke execute on function public.create_publish_batch(text, text, text, uuid[]), public.dry_run_publish_batch(text, int, int),
  public.approve_publish_batch(text, text), public.run_publish_batch(text), public.undo_publish_batch(text),
  public.publish_batch_summary(text, text), public._waiting_firms(text, text), public._waiting_enrichments(uuid),
  public._backup_review_match(uuid, text, text), public._firm_rules_n(uuid), public._firm_collisions_n(uuid)
  from public, anon, authenticated;

create or replace function public.promote_bot_facts(p_firm uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fn$
declare qid text := _firm_queue_id(p_firm); k record; rec record; fid uuid; n int := 0;
  hv text; v text; xr text; hl text; src jsonb; sid uuid; i int;
begin
  if qid is null then return 0; end if;
  -- check history is kept: nothing is deleted from publish_checks
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
    -- keep the old value so a batch undo can put it back; record a new card as added by this batch
    if exists (select 1 from firm_profile_facts where id = fid) then
      if exists (select 1 from firm_profile_facts where id = fid and origin like 'promoted from submission %' and value is distinct from left(v, 400)) then
        insert into cleanup_backup(batch, firm_id, table_name, row_id, row_data)
        select 'publish:' || coalesce(nullif(current_setting('app.publish_batch', true), ''), 'none'), p_firm, 'firm_profile_facts', fid, to_jsonb(x) from firm_profile_facts x where id = fid;
      end if;
    else
      insert into enrichment_rows(firm_id, table_name, row_id, enrichment_id) values (p_firm, 'firm_profile_facts', fid, rec.sub) on conflict do nothing;
    end if;
    insert into publish_checks(origin, origin_id, firm_id, section, kind, field, item, outcome, reason, target_table, target_id)
    values ('submission', rec.sub, p_firm, k.sec, 'record', k.fp, rec.r, 'published', null, 'firm_profile_facts', fid);
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
end $fn$
;
revoke execute on function public.promote_bot_facts(uuid) from public, anon, authenticated;
