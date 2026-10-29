-- Fix 3b: log the true outcome after a write. If the fix 3 one-home guard dropped a row
-- (recorded in money_home_blocked), the log says 'blocked' plus the guard's reason, never 'published'.
-- Old publish_checks rows are not rewritten.

alter table public.publish_checks drop constraint publish_checks_outcome_check;
alter table public.publish_checks add constraint publish_checks_outcome_check
  check (outcome = any (array['published','merged','conflict','rejected','note','held','blocked']));
alter table public.money_home_blocked add column if not exists row_id uuid;

-- reason the guard gave for dropping this row in this transaction, or null if it was not dropped
create or replace function public._money_home_dropped(p_table text, p_id uuid)
returns text language sql stable security definer set search_path to 'public' as $$
  select b.reason from public.money_home_blocked b
   where p_id is not null and b.row_id = p_id and b.table_name = p_table and b.created_at = now()
   order by b.id desc limit 1 $$;
-- latest guard reason for this firm in this transaction after a mark (for writes whose row id is not known)
create or replace function public._money_home_since(p_firm uuid, p_mark bigint)
returns text language sql stable security definer set search_path to 'public' as $$
  select b.reason from public.money_home_blocked b
   where b.firm_id = p_firm and b.id > coalesce(p_mark, 0) and b.created_at = now()
   order by b.id desc limit 1 $$;
create or replace function public._money_home_mark()
returns bigint language sql stable security definer set search_path to 'public' as $$
  select coalesce(max(id), 0) from public.money_home_blocked $$;
revoke all on function public._money_home_dropped(text, uuid), public._money_home_since(uuid, bigint), public._money_home_mark() from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public._money_home_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare lbl text; val text; k text; a numeric; c text; fid uuid; routed text; why text; done int;
begin
  fid := new.firm_id;
  if tg_table_name = 'firm_profile_facts' then
    lbl := case when public._money_home_label(new.label) then new.label when public._money_home_label(new.hero_label) then new.hero_label end;
    if tg_op = 'UPDATE' and (public._money_home_label(old.label) or public._money_home_label(old.hero_label)) then return new; end if;
    val := concat_ws(' · ', new.hero_value, new.value);
  elsif tg_table_name = 'vc_source_facts' then
    lbl := case when public._money_home_label(new.fact_type) then new.fact_type
                when public._money_home_label(new.value->>'field') then new.value->>'field'
                when public._money_home_label(new.value->>'label') then new.value->>'label' end;
    if tg_op = 'UPDATE' and (public._money_home_label(old.fact_type) or public._money_home_label(old.value->>'field') or public._money_home_label(old.value->>'label')) then return new; end if;
    val := coalesce(new.value->>'value', new.value::text);
  elsif tg_table_name = 'list_items' then
    lbl := case when public._money_home_label(new.group_key) then new.group_key when public._money_home_label(new.name) then new.name end;
    if tg_op = 'UPDATE' and (public._money_home_label(old.group_key) or public._money_home_label(old.name)) then return new; end if;
    val := concat_ws(' · ', new.value, new.note);
  else -- timeline_events: the kind, or a "Label: value" style body
    lbl := case when public._money_home_label(new.kind) then new.kind
                when public._money_home_label(substring(new.body from '^\s*([^:·—]{2,40}?)\s*[:·—]')) then substring(new.body from '^\s*([^:·—]{2,40}?)\s*[:·—]') end;
    if tg_op = 'UPDATE' and (public._money_home_label(old.kind) or public._money_home_label(substring(old.body from '^\s*([^:·—]{2,40}?)\s*[:·—]'))) then return new; end if;
    val := new.body;
  end if;
  if lbl is null then return new; end if;
  k := public._money_home_kind(lbl);
  select amount, currency into a, c from public._money_home_full(val);
  -- Per-fund gross assets ("Fund gross assets") are not the firm total: never routed.
  if a is null or fid is null or (k = 'fund_assets' and lower(lbl) !~ '^(total |private fund )?(fund assets|gross assets|gav|private fund gav)') then
    why := 'no full number plus currency code for the firm total, so nothing was routed';
  elsif k = 'aum' then
    update public.firms set aum_amount = a, aum_currency = c where id = fid and aum_amount is null;
    get diagnostics done = row_count;
    if done > 0 then routed := 'firms.aum_amount'; why := 'routed to firms.aum_amount/aum_currency';
    else why := 'firm already has an AUM in firms.aum_amount; kept the existing value'; end if;
  else
    update public.firms set fund_assets_amount = a, fund_assets_currency = c where id = fid and fund_assets_amount is null;
    get diagnostics done = row_count;
    if done > 0 then routed := 'firms.fund_assets_amount'; why := 'routed to firms.fund_assets_amount/fund_assets_currency';
    else why := 'firm already has Fund assets in firms.fund_assets_amount; kept the existing value'; end if;
  end if;
  if routed is not null then delete from public.firm_page_cache where firm_id = fid; end if;
  insert into public.money_home_blocked(table_name, op, firm_id, label, value, routed_to, reason, row_id)
  values (tg_table_name, tg_op, fid, left(lbl, 200), left(val, 500), routed,
          'One home per field (fix 3): ' || case when k = 'aum' then 'AUM' else 'Fund assets' end
          || ' is stored only in firms.' || k || '_amount/' || k || '_currency, not as a ' || tg_table_name || ' row labelled "' || left(lbl, 60) || '". Row not stored; ' || why || '.', new.id);
  return null;
end $function$
;

CREATE OR REPLACE FUNCTION public._pc(p_eid bigint, p_bot text, p_firm uuid, p_sec text, p_kind text, p_field text, p_item jsonb, p_outcome text, p_reason text, p_table text, p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare why text;
begin
  -- fix 3b: a 'published' row is confirmed saved; if the one-home guard dropped it, log 'blocked' + reason
  if p_outcome = 'published' then why := public._money_home_dropped(p_table, p_id); end if;
  insert into publish_checks(origin, origin_id, bot_id, firm_id, section, kind, field, item, outcome, reason, target_table, target_id)
  values ('enrichment', p_eid, p_bot, p_firm, p_sec, p_kind, p_field, p_item,
          case when why is not null then 'blocked' else p_outcome end, coalesce(why, p_reason), p_table, p_id);
end $function$;

CREATE OR REPLACE FUNCTION public.promote_bot_facts(p_firm uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'bots', 'public'
AS $function$
declare qid text := _firm_queue_id(p_firm); k record; rec record; fid uuid; n int := 0;
  hv text; v text; xr text; hl text; src jsonb; sid uuid; i int;
begin
  if qid is null then return 0; end if;
  -- check history is kept: nothing is deleted from publish_checks
  -- Fix 3: AUM no longer becomes a profile card; it goes to its one home (firms.aum_amount / fund_assets_amount).
  n := n + public._route_aum_record(p_firm, qid);
  for k in select * from (values ('hq', 'overview', 'Headquarters', 'HQ', array['HQ'], 0)) t(fp, sec, lbl, hl, same, so) loop
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
    insert into firm_profile_facts(id, firm_id, section, label, value, hero_label, hero_value, sort_order, origin)
    values (fid, p_firm, k.sec, k.lbl, left(v, 400), hl, left(hv, 60), k.so, 'promoted from submission ' || rec.sub)
    on conflict (id) do update set value = excluded.value, hero_label = excluded.hero_label, hero_value = excluded.hero_value, origin = excluded.origin
      where firm_profile_facts.origin like 'promoted from submission %';
    -- fix 3b: log after the write, with the true outcome
    insert into publish_checks(origin, origin_id, firm_id, section, kind, field, item, outcome, reason, target_table, target_id)
    values ('submission', rec.sub, p_firm, k.sec, 'record', k.fp, rec.r,
            case when public._money_home_dropped('firm_profile_facts', fid) is not null then 'blocked' else 'published' end,
            public._money_home_dropped('firm_profile_facts', fid), 'firm_profile_facts', fid);
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
end $function$
;

CREATE OR REPLACE FUNCTION public._checker_place(p_firm uuid, p_section text, p_f jsonb, p_url text, p_level smallint, p_check integer, p_origin bigint)
 RETURNS TABLE(outcome text, reason text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'bots', 'public'
AS $function$
declare kept uuid; mk bigint; why text; old_text text; new_text text; old_level smallint; old_date text; new_date text;
  new_wins boolean; raw_new text; raw_old text;
begin
  new_text := public._checker_item_text(p_section, p_f);
  new_date := nullif(p_f->>'date', '');
  raw_new := coalesce(p_f->>'headline', p_f->>'event', p_f->>'role', p_f->>'value', p_f->>'name', p_f->>'title', p_f->>'quote', '');
  if p_section = 'press' then
    select p.id, public._norm_txt(p.headline), p.published_label, p.headline
      into kept, old_text, old_date, raw_old
      from press_items p join press_item_firms pf on pf.press_item_id = p.id
     where pf.firm_id = p_firm and public._checker_url_key(p.url) = public._checker_url_key(p_url)
     order by coalesce(pf.hidden, false), p.id limit 1;
  elsif p_section = 'people' then
    select r.id, public._norm_txt(r.role), null::text, r.role into kept, old_text, old_date, raw_old
      from firm_people_roles r
     where r.firm_id = p_firm and r.kind = coalesce(p_f->>'kind', 'officer')
       and r.stable_key = public._person_key(p_f->>'name')
     order by coalesce(r.hidden, false), r.id limit 1;
  elsif p_section = 'overview' then
    select f.id, public._norm_txt(f.value), null::text, f.value into kept, old_text, old_date, raw_old
      from firm_profile_facts f
     where f.firm_id = p_firm and f.section = 'overview'
       and public._norm_txt(coalesce(f.label, f.hero_label)) = public._norm_txt(p_f->>'label')
     order by coalesce(f.hidden, false), f.id limit 1;
  elsif p_section = 'legal' then
    select i.id, public._norm_txt(i.title), i.year_label, i.title into kept, old_text, old_date, raw_old
      from firm_legal_items i
     where i.firm_id = p_firm and i.stable_key = public._legal_key(p_f->>'title')
     order by coalesce(i.hidden, false), i.id limit 1;
  elsif p_section = 'timeline' then
    select t.id, public._norm_txt(t.body), t.date_label, t.body into kept, old_text, old_date, raw_old
      from timeline_events t
     where t.firm_id = p_firm and (
       public._checker_url_key(t.source_url) = public._checker_url_key(p_url)
       or t.stable_key = public._timeline_key(p_f->>'date', p_f->>'event'))
     order by coalesce(t.hidden, false), t.id limit 1;
  elsif p_section = 'founders' then
    select r.id, public._norm_txt(r.body), null::text, r.body into kept, old_text, old_date, raw_old
      from reviews r
     where r.firm_id = p_firm and p_url = any(coalesce(r.source_urls, '{}'))
     order by r.id limit 1;
  elsif p_section in ('funds', 'lps') then
    select f.id, public._norm_txt(f.value), null::text, f.value into kept, old_text, old_date, raw_old
      from firm_profile_facts f
     where f.firm_id = p_firm and f.section = p_section
       and (public._norm_txt(coalesce(f.label, f.hero_label, f.value)) = public._norm_txt(coalesce(p_f->>'name', p_f->>'label'))
            or (p_section = 'funds' and f.stable_key = public._fund_key(coalesce(p_f->>'name', ''))))
     order by coalesce(f.hidden, false), f.id limit 1;
  end if;
  select m.source_level into old_level from checker_marks m
   where m.firm_id = p_firm and m.kind = p_section and (m.url = p_url or m.item_key = p_section || '|' || coalesce(nullif(p_url, ''), left(p_f::text, 200)))
   order by m.checked_on desc limit 1;
  if kept is null then
    mk := public._money_home_mark();
    perform public._checker_write(p_firm, p_section, p_f, p_url, p_level, p_check);
    why := public._money_home_since(p_firm, mk);  -- fix 3b: confirm the row was saved
    if why is not null then outcome := 'blocked'; reason := why; return next; return; end if;
    outcome := 'published'; reason := null; return next; return;
  end if;
  if old_text is not distinct from new_text then
    perform public._checker_keep_one_exact(p_firm);
    outcome := 'skipped'; reason := 'exact duplicate, kept one'; return next; return;
  end if;
  old_level := coalesce(old_level, 4);
  if p_level < old_level then new_wins := true;
  elsif p_level > old_level then new_wins := false;
  elsif new_date is not null and old_date is not null and new_date > old_date then new_wins := true;
  elsif new_date is not null and old_date is not null and new_date < old_date then new_wins := false;
  elsif length(raw_new) > length(coalesce(raw_old, '')) then new_wins := true;
  elsif length(raw_new) < length(coalesce(raw_old, '')) then new_wins := false;
  else
    perform public._checker_note(p_firm, p_section, p_origin, raw_new, raw_old, 'undecided: same level, date, and length');
    outcome := 'note'; reason := 'undecided, kept the row already on the page'; return next; return;
  end if;
  if new_wins then
    if p_section = 'press' then
      update press_items set headline = left(coalesce(p_f->>'headline', ''), 400), snippet = left(p_f->>'snippet', 600),
             published_label = coalesce(new_date, published_label) where id = kept;
    elsif p_section = 'people' then
      update firm_people_roles set role = left(coalesce(p_f->>'role', ''), 300) where id = kept;
    elsif p_section = 'overview' then
      update firm_profile_facts set value = left(coalesce(p_f->>'value', ''), 400) where id = kept;
    elsif p_section = 'legal' then
      update firm_legal_items set title = left(coalesce(p_f->>'title', ''), 300) where id = kept;
    elsif p_section = 'timeline' then
      update timeline_events set body = left(coalesce(p_f->>'event', ''), 300), date_label = coalesce(new_date, date_label) where id = kept;
    elsif p_section = 'founders' then
      update reviews set body = left(coalesce(p_f->>'quote', ''), 2000) where id = kept;
    elsif p_section in ('funds', 'lps') then
      update firm_profile_facts set value = left(coalesce(p_f->>'name', p_f->>'value', ''), 400) where id = kept;
    end if;
    perform public._checker_stamp(p_section, p_firm, kept, p_level);
    perform public._checker_note(p_firm, p_section, p_origin, raw_old, raw_new, 'merged: new value won, old value kept as a note');
    insert into checker_marks(firm_id, kind, item_key, checked_by, source_level, url)
    values (p_firm, p_section, p_section || '|' || coalesce(nullif(p_url, ''), left(p_f::text, 200)), 'Checker', p_level, p_url)
    on conflict (firm_id, kind, item_key) do update set source_level = least(checker_marks.source_level, excluded.source_level), checked_on = now();
    outcome := 'merged'; reason := 'new value won'; return next; return;
  end if;
  perform public._checker_note(p_firm, p_section, p_origin, raw_new, raw_old, 'merged: page value won, new value kept as a note');
  outcome := 'note'; reason := 'page value won'; return next;
end $function$
;

CREATE OR REPLACE FUNCTION public.checker_publish_submission(p_id bigint, p_probes jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'bots', 'public'
AS $function$
declare sub bots.research_submissions; fid uuid; it record; lvl smallint; ncheck int; outcome text; reason text;
  pub int := 0; skip int := 0; fail int := 0; unconf int := 0; merged int := 0; noted int := 0; internal int := 0; blocked int := 0;
  probes jsonb; gate jsonb; host text; claimed text; opened boolean; website boolean;
  reasons jsonb := '[]'::jsonb;
begin
  select * into sub from research_submissions where id = p_id;
  if sub.id is null or not public._checker_publish_on() then
    return jsonb_build_object('ran', false);
  end if;
  -- Step B (A5.5): only rows the entry check Accepted; flagged links are opened first.
  gate := public._checker_entry_gate(sub.id, p_probes);
  if gate is not null then return gate; end if;
  select * into sub from research_submissions where id = p_id;
  select f.id into fid from firms f
   where f.deleted_at is null and f.registry_id = coalesce(public._registry_target(sub.registry_id), sub.registry_id)
   order by f.published desc limit 1;
  if fid is null or not public._lab_firm(fid) then
    return jsonb_build_object('ran', false, 'reason', 'not a lab firm');
  end if;
  probes := coalesce(p_probes, sub.payload->'probes');
  for it in select * from public._checker_payload_items(sub.payload) loop
    begin
      claimed := null;
      website := it.section = 'overview' and lower(coalesce(it.f->>'label', '')) in ('website', 'primary_domain');
      if website then
        host := public._dom(it.url);
        claimed := public._checker_host(it.f->>'value');
        if public.source_tier(it.url) is null then
          lvl := null; outcome := 'failure'; reason := 'link is not real (missing, not http, or a search/chat page)';
        elsif host is null or claimed is null or not (host = claimed or host like '%.' || claimed) then
          lvl := null; outcome := 'failure'; reason := 'link does not match the firm';
        else
          opened := public._checker_link_opens(it.url, probes);
          if opened is null then
            lvl := null; outcome := 'failure'; reason := 'link was not opened';
          elsif not opened then
            lvl := null; outcome := 'failure'; reason := 'link did not open';
          else
            lvl := 2; outcome := 'published'; reason := null;
          end if;
        end if;
      elsif it.section = 'social' then
        ncheck := null;
        select d.lvl, d.outcome, d.reason into lvl, outcome, reason from public._checker_social(fid, it.f || jsonb_build_object('submission_id', p_id), it.url) d;
      else
        ncheck := public._checker_check_n(it.section, it.url);
        select d.lvl, d.outcome, d.reason into lvl, outcome, reason
          from public._checker_decide(fid, it.section, it.f, it.url, ncheck, probes) d;
      end if;
      if outcome = 'published' and it.section <> 'social' then
        select p.outcome, p.reason into outcome, reason
          from public._checker_place(fid, it.section, it.f, it.url, lvl, ncheck, sub.id) p;
      end if;
      if website and outcome in ('published', 'merged', 'skipped') and claimed is not null then
        update firms set primary_domain = claimed
         where id = fid and (primary_domain is null or lower(primary_domain) = claimed);
      end if;
    exception when others then
      outcome := 'failure'; reason := sqlerrm;
    end;
    -- our own write / DB-constraint errors are not the bot's fault: counted apart, never as a failure
    if outcome = 'failure' and public._checker_internal_error(reason) then outcome := 'internal'; end if;
    if outcome = 'published' then pub := pub + 1;
    elsif outcome = 'merged' then merged := merged + 1;
    elsif outcome = 'note' then noted := noted + 1;
    elsif outcome = 'skipped' then skip := skip + 1;
    elsif outcome = 'unconfirmed' then unconf := unconf + 1;
    elsif outcome = 'internal' then internal := internal + 1;
    elsif outcome = 'blocked' then blocked := blocked + 1;
    else fail := fail + 1; end if;
    if outcome is distinct from 'published' and outcome is distinct from 'merged' then
      reasons := reasons || jsonb_build_array(jsonb_build_object('section', it.section, 'url', coalesce(it.f->>'url', it.url),
        'outcome', coalesce(outcome, 'failure'), 'reason', coalesce(reason, 'no reason given')));
    end if;
    if outcome in ('failure', 'unconfirmed', 'internal') then
      insert into checker_holding(firm_id, origin, origin_id, kind, url, outcome, reason, item)
      values (fid, 'submission', sub.id, it.section, it.url,
              case when outcome = 'unconfirmed' then 'unconfirmed' else 'failure' end, reason, it.f);
    end if;
  end loop;
  return jsonb_build_object('ran', true, 'firm_id', fid, 'published', pub, 'merged', merged, 'note', noted,
    'skipped', skip, 'unconfirmed', unconf, 'failure', fail, 'internal', internal, 'blocked', blocked, 'reasons', reasons);
end $function$
;

CREATE OR REPLACE FUNCTION public.checker_publish_firm(p_firm uuid, p_write boolean DEFAULT false, p_probes jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'bots', 'public'
AS $function$
declare e bots.research_enrichments; it record; lvl smallint; n int; url text; outcome text; reason text;
  pub int := 0; held int := 0; fail int := 0; skip int := 0; unconf int := 0; mk bigint; why text; blk int := 0;
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
    select d.lvl, d.outcome, d.reason into lvl, outcome, reason
      from public._checker_decide(p_firm, it.section, it.f, url, n, p_probes) d;
    if outcome = 'published' and public._checker_exists(p_firm, it.section, it.f, url) then
      outcome := 'skipped'; reason := 'already on the page, not re-checked';
    end if;
    if outcome = 'published' and p_write then
      begin
        mk := public._money_home_mark();
        perform public._checker_write(p_firm, it.section, it.f, url, lvl, n);
        why := public._money_home_since(p_firm, mk);  -- fix 3b
        if why is not null then outcome := 'blocked'; reason := why; end if;
      exception when others then
        outcome := 'failure'; reason := 'write failed: ' || sqlerrm;
      end;
    end if;
    if outcome = 'published' then pub := pub + 1;
    elsif outcome = 'unconfirmed' then unconf := unconf + 1; held := held + 1;
    elsif outcome = 'failure' then fail := fail + 1;
    elsif outcome = 'blocked' then blk := blk + 1;
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
    'published', pub, 'unconfirmed', unconf, 'held', held, 'failure', fail, 'skipped', skip, 'blocked', blk,
    'submissions_in_holding', (select count(*) from research_submissions s
       where s.registry_id = (select registry_id from firms where id = p_firm)),
    'header', jsonb_build_object('name', (select coalesce(display_name, name) from firms where id = p_firm),
      'short_name', (select short_name from firms where id = p_firm),
      'website', dom, 'hq', hq, 'hq_source_level', hq_level),
    'match', (select jsonb_build_object('firm_id', m.firm_id, 'note', m.note)
                from public.checker_match_firm((select registry_id from firms where id = p_firm), dom,
                     (select name from firms where id = p_firm), hq) m limit 1));
end $function$
;
