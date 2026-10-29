-- Rollback fix 7. Puts the Checker, promote, the entry check, and the check 8 pill back.
-- Drops the headquarters columns. Values stored there go away with the columns.
-- The old headquarters text and the old profile rows stay.

drop trigger if exists hq_home_guard on public.firm_profile_facts;
drop trigger if exists hq_home_guard on public.vc_source_facts;
drop trigger if exists hq_home_guard on public.list_items;
drop trigger if exists hq_home_guard on public.timeline_events;

CREATE OR REPLACE FUNCTION public._checker_write(p_firm uuid, p_section text, p_f jsonb, p_url text, p_level smallint, p_check integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rid uuid := gen_random_uuid(); key text; n int := p_check; lab boolean := public._lab_firm(p_firm); acct text;
begin
  key := p_section || '|' || coalesce(nullif(p_url, ''), left(p_f::text, 200));
  if p_section = 'press' then
    insert into press_items(id, publisher, domain, url, published_label, headline, snippet, data_status, retrieved_at, source_system)
    values (rid, coalesce(p_f->>'outlet', public.source_label(public._dom(p_url), p_url)), public._dom(p_url), p_url,
            p_f->>'date', left(coalesce(p_f->>'headline', ''), 400), left(p_f->>'snippet', 600), 'real', now(), 'checker');
    insert into press_item_firms(press_item_id, firm_id, sort_order, check_mark, checked_on, checked_by, source_level)
    values (rid, p_firm, 900, 'checked_correct', case when lab then now() end, case when lab then 'Checker' end, case when lab then p_level end);
  elsif p_section = 'timeline' then
    insert into timeline_events(id, firm_id, date_label, kind, body, sort_order, source_url, check_mark, checked_on, checked_by, source_level)
    values (rid, p_firm, p_f->>'date', 'Reported', left(coalesce(p_f->>'event', ''), 300), 900, p_url, 'checked_correct',
            case when lab then now() end, case when lab then 'Checker' end, case when lab then p_level end);
  elsif p_section = 'people' then
    insert into firm_people_roles(id, firm_id, kind, person_name, role, sort_order, checked_on, checked_by, source_level)
    values (rid, p_firm, coalesce(p_f->>'kind', 'officer'), left(p_f->>'name', 120), left(coalesce(p_f->>'role', ''), 300), 900,
            case when lab then now() end, case when lab then 'Checker' end, case when lab then p_level end);
  elsif p_section = 'social' then
    -- socialAccounts (A2.10 / B3.8): a level-2 media_reach fact like the #263 General Catalyst row. Never firm_profile_facts.
    acct := public._checker_social_platform(p_f->>'platform');
    key := 'social|' || coalesce(p_f->>'url', '');
    insert into vc_source_facts(id, firm_id, fact_type, section, value, source_url, source_label, source_type, retrieved_at, data_status,
                                source_system, external_id, checked_on, checked_by, source_level)
    values (rid, p_firm, 'media_reach', 'media_reach',
            jsonb_build_object('field', 'media_' || acct || '_followers',
                               'value', (p_f->>'followers') || coalesce(' (@' || nullif(substring(p_f->>'url' from '^https?://[^/]+/(?:company/|@)?([^/?#]+)'), '') || ')', ''),
                               'url', p_f->>'url', 'entity', 'firm', 'publisher', initcap(acct),
                               'linked_from', coalesce(nullif(p_f->>'found_on_url', ''), p_url),
                               'linked_checked', coalesce(p_f->>'followers_read_at', to_char(now(), 'YYYY-MM-DD')),
                               'sheet_status', 'firm says'),
            p_f->>'url', initcap(acct), acct,
            coalesce((p_f->>'followers_read_at')::date::timestamptz, now()), 'real', 'checker',
            'checker:social:' || md5(p_firm::text || '|' || acct || '|' || public._checker_url_key(p_f->>'url')),
            case when lab then now() end, case when lab then 'Checker' end, 2);
  elsif p_section in ('overview', 'funds', 'lps') then
    insert into firm_profile_facts(id, firm_id, section, label, value, sort_order, origin, checked_on, checked_by, source_level)
    values (rid, p_firm, p_section,
            case p_section when 'overview' then p_f->>'label' when 'lps' then p_f->>'name' else 'Funds' end,
            left(case p_section when 'overview' then p_f->>'value' when 'lps' then p_f->>'name' else coalesce(p_f->>'name', '') end, 400),
            900, 'checker', case when lab then now() end, case when lab then 'Checker' end, case when lab then p_level end);
  elsif p_section = 'legal' then
    -- Fix 5: an SEC adviser summary is not a regulator action. Do not write it.
    if public._sec_adviser_summary('regulator', coalesce(p_f->>'title', '')) then
      perform public._block_sec_summary(p_firm, 'checker', coalesce(p_f->>'title', ''), null);
      return null;
    end if;
    insert into firm_legal_items(id, firm_id, grp, title, year_label, status_label, sort_order, checked_on, checked_by, source_level)
    values (rid, p_firm, 'context', left(coalesce(p_f->>'title', ''), 300), substring(p_f->>'date' from '^(\d{4})'), p_f->>'status', 900,
            case when lab then now() end, case when lab then 'Checker' end, case when lab then p_level end);
  elsif p_section = 'founders' then
    insert into reviews(id, firm_id, body, first_hand, verification_status, moderation_status, anonymous, author_name, source_urls,
                        review_type, is_public, source_system, dedupe_key, checked_on, checked_by, source_level)
    values (rid, p_firm, left(coalesce(p_f->>'quote', ''), 2000), false, 'unverified', 'approved', false,
            left(p_f->>'who', 200), array[p_url], 'founder', true, 'checker', 'url:' || left(p_url, 400),
            case when lab then now() end, case when lab then 'Checker' end, case when lab then p_level end);
  elsif n is not null then
    insert into vc_source_facts(firm_id, fact_type, section, value, source_url, source_label, retrieved_at, data_status, source_system, external_id,
                                checked_on, checked_by, source_level)
    values (p_firm,
            case when n in (1, 2, 10) then 'sanctions_check' when n in (4, 5) then 'regulatory_record' when n = 8 then 'fund_fact' else 'legal_matter' end,
            'checks',
            jsonb_build_object('field', case n when 1 then 'sanctions' when 2 then 'terrorism_lists' when 3 then 'export_restrictions'
              when 4 then 'regulatory_action' when 5 then 'aml_penalties' when 7 then 'courts_worldwide' when 8 then 'registration_status'
              when 9 then 'people_screen' when 10 then 'pep' else 'legal_matter' end, 'value', left(p_f::text, 500)),
            p_url, 'Checker', now(), 'real', 'checker', 'checker:' || p_firm::text || ':' || n::text || ':' || md5(coalesce(p_url, '') || p_f::text),
            case when lab then now() end, case when lab then 'Checker' end, case when lab then p_level end);
    rid := gen_random_uuid();
  else
    return null;
  end if;
  insert into checker_marks(firm_id, kind, item_key, checked_by, source_level, url)
  values (p_firm, coalesce(p_section, 'check'), key, 'Checker', p_level, p_url)
  on conflict (firm_id, kind, item_key) do nothing;
  return rid;
end $function$;

CREATE OR REPLACE FUNCTION public._checker_place(p_firm uuid, p_section text, p_f jsonb, p_url text, p_level smallint, p_check integer, p_origin bigint)
 RETURNS TABLE(outcome text, reason text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'bots', 'public'
AS $function$
declare kept uuid; mk bigint; why text; old_text text; new_text text; old_level smallint; old_date text; new_date text;
  new_wins boolean; raw_new text; raw_old text;
begin
  -- Fix 5: do not publish or merge an SEC adviser summary over a legal row.
  if p_section = 'legal' and public._sec_adviser_summary('regulator', coalesce(p_f->>'title', '')) then
    perform public._block_sec_summary(p_firm, 'checker', coalesce(p_f->>'title', ''), null);
    outcome := 'blocked';
    reason := public._sec_summary_reason();
    return next; return;
  end if;
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
end $function$;

CREATE OR REPLACE FUNCTION public._entry_check_reasons(p jsonb, p_firm_dom text)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  r text[] := '{}';
  it record; recs jsonb; rec jsonb; raw jsonb; lvl int; sec text;
  dom text := nullif(regexp_replace(lower(coalesce(p_firm_dom, '')), '^www\.', ''), '');
begin
  if p is null or jsonb_typeof(p) <> 'object' then return array['empty or unreadable upload']; end if;
  recs := case when jsonb_typeof(p->'records') = 'array' then p->'records' else '[]'::jsonb end;

  if not exists (select 1 from public._checker_payload_items(p)) then
    r := r || 'no items in the upload'::text;
  end if;

  for it in select * from public._checker_payload_items(p) loop
    rec := case when it.n >= 1 and jsonb_typeof(p->'records') = 'array' then recs->(it.n - 1) else null end;
    sec := public._entry_section(it.section, rec->>'field_path');
    -- 1) link present and well-formed http(s)
    if it.url is null or btrim(it.url) = '' then
      r := r || 'no source link'::text;
    elsif btrim(it.url) !~* '^https?://[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+(:\d+)?([/?#][^\s]*)?$' then
      r := r || 'source link is not a valid http(s) URL'::text;
    elsif public._src_search_page(it.url) then
      r := r || 'source link is a search or chat page'::text;
    end if;
    -- 2) source level 1 to 3
    -- Sections shape: the parsed item drops tier/source_level, so read them from the raw item (fix, step B).
    raw := case when rec is null and jsonb_typeof(p->'sections') = 'object'
                then (select c.item from public.checked_items(p) c where c.n = it.n and c.outcome = 'ok' limit 1) end;
    lvl := case when it.n = 0 then 2 else public._entry_level(rec, coalesce(raw, it.f)) end;  -- n = 0: the firm's own website item
    if lvl is null then r := r || 'no source level'::text;
    elsif lvl not between 1 and 3 then r := r || ('source level ' || lvl || ' is not 1 to 3')::text;
    end if;
    -- 4) dates: never rejected; normalized or cleared by _entry_fix_payload.
    -- 5) status words
    if it.section = 'legal' and public._entry_status_bad(it.f) is not null then r := r || public._entry_status_bad(it.f); end if;
    -- 5b) AUM basis press removed (A7.3)
    if rec->>'field_path' = 'aum' and lower(coalesce(rec->'value'->>'basis', '')) = 'press' then
      r := r || 'AUM basis press is not allowed (A7.3)'::text;
    end if;
    -- 5e) fix 5: the IAPD adviser summary is not a regulator action
    if coalesce(rec->>'field_path', '') = 'regulatoryActions'
       and public._sec_adviser_summary('regulator', coalesce(rec->'value'->>'title', rec->'value'->>'summary', rec->'value'->>'caption', it.f->>'title', '')) then
      r := r || public._sec_summary_reason();
    end if;
    -- 5c) A15.8 money: full number plus currency, never short forms (same rules as research-ingest moneyChecks)
    r := r || public._money_problems(rec->>'field_path', rec->'value');
    -- 5d) fix 3, one home per field: AUM / RAUM / fund assets only in the aum record (same rule as research-ingest homeChecks)
    if coalesce(rec->>'field_path', '') <> 'aum' and public._money_home_item(rec, it.f) is not null then
      r := r || ('AUM and fund assets have one home: send them only as field_path "aum" (amount_usd, raum_usd, private_fund_gav_usd, or amount + currency), not as "'
                 || left(public._money_home_item(rec, it.f), 40) || '" (fix 3)')::text;
    end if;
    -- 6b) thesis over 1,000 characters (A9.19): never rejected; cut by _entry_fix_payload.
    -- 7) no news from the firm's own site
    if sec in ('press', 'news', 'timeline') and dom is not null and it.url is not null
       and (public._dom(it.url) = dom or public._dom(it.url) like '%.' || dom) then
      r := r || 'news item from the firm''s own website or blog'::text;
    end if;
  end loop;

  -- 6) A9 list limits: never rejected; extra items archived by _entry_fix_payload.

  return (select coalesce(array_agg(x order by o), '{}') from (select x, min(o) o from unnest(r) with ordinality u(x, o) group by x) s);
end $function$;

create or replace function public._lab_live_pill(p_firm uuid, p_n int)
returns table(state text, count_label text, why text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare
  looked boolean; sub bigint; fin int := 0; sav int := 0; items int := 0; hot int := 0;
  iapd text; v_state text; v_count text; v_why text; stored_st text; stored_cnt text;
begin
  select (r.searched_at is not null or r.checked_on is not null), r.source_submission, r.state, r.count_label
    into looked, sub, stored_st, stored_cnt
  from firm_check_rows r where r.firm_id = p_firm and r.n = p_n;
  if not found then
    return query select 'nc'::text, null::text, 'no check row'::text;
    return;
  end if;

  if sub is not null then
    select count(*)::int into fin from check_findings(sub) c where c.k = p_n;
  end if;
  select count(*)::int into sav from check_saved_items(p_firm, p_n);
  items := case when fin > 0 then fin else sav end;

  if p_n = 8 then
    select v.value->>'value' into iapd
    from vc_source_facts v
    where v.firm_id = p_firm and v.superseded_by is null
      and v.value->>'field' = 'registration_status'
      and coalesce(v.source_url, '') ~* 'adviserinfo\.sec\.gov|sec\.gov'
      and coalesce(v.value->>'value', '') !~* 'separate adviser|relying adviser'
      and coalesce(v.value->>'value', '') ~* 'SEC-registered|Exempt reporting|\mERA\M|Registered, Approved|status Approved'
    order by v.retrieved_at desc nulls last
    limit 1;
    if iapd is null then
      select p.value into iapd
      from firm_profile_facts p
      join fact_sources fs on fs.fact_type = 'firm_profile_facts' and fs.fact_id = p.id
      join sources s on s.id = fs.source_id and s.url ~* 'adviserinfo\.sec\.gov'
      where p.firm_id = p_firm and not p.hidden
        and p.value ~* 'SEC-registered|Exempt Reporting Adviser|Exempt reporting adviser'
      order by p.sort_order
      limit 1;
    end if;
    if iapd is not null then
      v_state := 'clear'; v_count := null; v_why := 'IAPD registration row';
    else
      v_state := 'nc'; v_count := null; v_why := 'no IAPD registration row';
    end if;
  elsif items > 0 and p_n = 6 then
    if fin > 0 then
      select count(*)::int into hot from check_findings(sub) c
       where c.k = 6 and coalesce(c.status, '') ~* 'active|open|pending|ongoing'
         and coalesce(c.status, '') !~* '^(dismissed|closed|settled|withdrawn)';
    else
      select count(*)::int into hot from check_saved_items(p_firm, 6) c
       where coalesce(c.status, '') ~* 'active|open|pending|ongoing'
         and coalesce(c.status, '') !~* '^(dismissed|closed|settled|withdrawn)';
    end if;
    if hot > 0 then
      v_state := 'review'; v_why := 'a finding is active, open, or pending';
    else
      v_state := 'wk'; v_why := 'findings are closed cases';
    end if;
    if hot > 0 and hot = items then
      v_count := case when items = 1 then '1 active case' else items::text || ' active cases' end;
    else
      v_count := case when items = 1 then '1 case' else items::text || ' cases' end;
    end if;
  elsif items > 0 and p_n = 4 then
    v_state := 'review';
    if fin > 0 then
      select count(*)::int into hot from check_findings(sub) c
       where c.k = 4 and coalesce(c.status, '') ~* 'open|probe'
         and coalesce(c.status, '') !~* 'settled|closed';
    else
      select count(*)::int into hot from check_saved_items(p_firm, 4) c
       where coalesce(c.status, '') ~* 'open|probe'
         and coalesce(c.status, '') !~* 'settled|closed';
    end if;
    if hot > 0 then
      v_count := case when hot = 1 then '1 open probe' else hot::text || ' open probes' end;
      v_why := 'open regulator findings';
    else
      v_count := case when items = 1 then '1 action' else items::text || ' actions' end;
      v_why := 'regulator findings';
    end if;
  elsif items > 0 and p_n = 10 then
    v_state := 'wk';
    v_count := case when items = 1 then '1 record' else items::text || ' records' end;
    v_why := 'political-tie findings';
  elsif items > 0 and p_n = 9 then
    v_state := 'review';
    v_count := case when items = 1 then '1 finding' else items::text || ' findings' end;
    v_why := 'people-screen findings';
  elsif items > 0 and p_n = 7 then
    v_state := 'clear';
    v_count := case when items = 1 then '1 non-party mention' else items::text || ' non-party mentions' end;
    v_why := 'non-US findings';
  elsif items > 0 then
    v_state := 'review';
    v_count := case when items = 1 then '1 record' else items::text || ' records' end;
    v_why := 'findings on this check';
  elsif looked then
    v_state := case when p_n = 10 then 'nf' else 'clear' end;
    v_count := null;
    v_why := 'searched, no findings';
  else
    v_state := 'nc';
    v_count := null;
    v_why := 'no findings and this check was not searched';
  end if;

  if v_state = stored_st and stored_cnt is not null and v_count is not null
     and (select count(*) from regexp_matches(stored_cnt, '\d+', 'g')) = 1
     and (regexp_match(stored_cnt, '\d+'))[1] = (regexp_match(v_count, '\d+'))[1]
  then
    v_count := stored_cnt;
  end if;

  return query select v_state, v_count, v_why;
end $$;

CREATE OR REPLACE FUNCTION public._lab_live_pill(p_firm uuid, p_n integer, p_fin integer, p_hot integer)
 RETURNS TABLE(state text, count_label text, why text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare
  looked boolean; sub bigint; fin int := 0; sav int := 0; items int := 0; hot int := 0;
  iapd text; v_state text; v_count text; v_why text; stored_st text; stored_cnt text;
begin
  select (r.searched_at is not null or r.checked_on is not null), r.source_submission, r.state, r.count_label
    into looked, sub, stored_st, stored_cnt
  from firm_check_rows r where r.firm_id = p_firm and r.n = p_n;
  if not found then
    return query select 'nc'::text, null::text, 'no check row'::text;
    return;
  end if;
  -- p_fin: findings for (sub, p_n) precomputed by the caller (0 when sub is null). null = compute here.
  if p_fin is not null then fin := p_fin;
  elsif sub is not null then
    select count(*)::int into fin from check_findings(sub) c where c.k = p_n;
  end if;
  select count(*)::int into sav from check_saved_items(p_firm, p_n);
  items := case when fin > 0 then fin else sav end;
  if p_n = 8 then
    select v.value->>'value' into iapd
    from vc_source_facts v
    where v.firm_id = p_firm and v.superseded_by is null
      and v.value->>'field' = 'registration_status'
      and coalesce(v.source_url, '') ~* 'adviserinfo\.sec\.gov|sec\.gov'
      and coalesce(v.value->>'value', '') !~* 'separate adviser|relying adviser'
      and coalesce(v.value->>'value', '') ~* 'SEC-registered|Exempt reporting|\mERA\M|Registered, Approved|status Approved'
    order by v.retrieved_at desc nulls last
    limit 1;
    if iapd is null then
      select p.value into iapd
      from firm_profile_facts p
      join fact_sources fs on fs.fact_type = 'firm_profile_facts' and fs.fact_id = p.id
      join sources s on s.id = fs.source_id and s.url ~* 'adviserinfo\.sec\.gov'
      where p.firm_id = p_firm and not p.hidden
        and p.value ~* 'SEC-registered|Exempt Reporting Adviser|Exempt reporting adviser'
      order by p.sort_order
      limit 1;
    end if;
    if iapd is not null then
      v_state := 'clear'; v_count := null; v_why := 'IAPD registration row';
    else
      v_state := 'nc'; v_count := null; v_why := 'no IAPD registration row';
    end if;
  elsif items > 0 and p_n = 6 then
    if fin > 0 and p_hot is not null then
      hot := p_hot;
    elsif fin > 0 then
      select count(*)::int into hot from check_findings(sub) c
       where c.k = 6 and coalesce(c.status, '') ~* 'active|open|pending|ongoing'
         and coalesce(c.status, '') !~* '^(dismissed|closed|settled|withdrawn)';
    else
      select count(*)::int into hot from check_saved_items(p_firm, 6) c
       where coalesce(c.status, '') ~* 'active|open|pending|ongoing'
         and coalesce(c.status, '') !~* '^(dismissed|closed|settled|withdrawn)';
    end if;
    if hot > 0 then v_state := 'review'; v_why := 'a finding is active, open, or pending';
    else v_state := 'wk'; v_why := 'findings are closed cases'; end if;
    if hot > 0 and hot = items then
      v_count := case when items = 1 then '1 active case' else items::text || ' active cases' end;
    else
      v_count := case when items = 1 then '1 case' else items::text || ' cases' end;
    end if;
  elsif items > 0 and p_n = 4 then
    v_state := 'review';
    if fin > 0 and p_hot is not null then
      hot := p_hot;
    elsif fin > 0 then
      select count(*)::int into hot from check_findings(sub) c
       where c.k = 4 and coalesce(c.status, '') ~* 'open|probe' and coalesce(c.status, '') !~* 'settled|closed';
    else
      select count(*)::int into hot from check_saved_items(p_firm, 4) c
       where coalesce(c.status, '') ~* 'open|probe' and coalesce(c.status, '') !~* 'settled|closed';
    end if;
    if hot > 0 then
      v_count := case when hot = 1 then '1 open probe' else hot::text || ' open probes' end;
      v_why := 'open regulator findings';
    else
      v_count := case when items = 1 then '1 action' else items::text || ' actions' end;
      v_why := 'regulator findings';
    end if;
  elsif items > 0 and p_n = 10 then
    v_state := 'wk'; v_count := case when items = 1 then '1 record' else items::text || ' records' end; v_why := 'political-tie findings';
  elsif items > 0 and p_n = 9 then
    v_state := 'review'; v_count := case when items = 1 then '1 finding' else items::text || ' findings' end; v_why := 'people-screen findings';
  elsif items > 0 and p_n = 7 then
    v_state := 'clear'; v_count := case when items = 1 then '1 non-party mention' else items::text || ' non-party mentions' end; v_why := 'non-US findings';
  elsif items > 0 then
    v_state := 'review'; v_count := case when items = 1 then '1 record' else items::text || ' records' end; v_why := 'findings on this check';
  elsif looked then
    v_state := case when p_n = 10 then 'nf' else 'clear' end; v_count := null; v_why := 'searched, no findings';
  else
    v_state := 'nc'; v_count := null; v_why := 'no findings and this check was not searched';
  end if;
  if v_state = stored_st and stored_cnt is not null and v_count is not null
     and (select count(*) from regexp_matches(stored_cnt, '\d+', 'g')) = 1
     and (regexp_match(stored_cnt, '\d+'))[1] = (regexp_match(v_count, '\d+'))[1]
  then v_count := stored_cnt; end if;
  return query select v_state, v_count, v_why;
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


alter table public.firms drop constraint if exists firms_hq_country_chk;
alter table public.firms drop constraint if exists firms_hq_source_level_chk;
alter table public.firms drop constraint if exists firms_hq_source_url_chk;
alter table public.firms
  drop column if exists hq_city,
  drop column if exists hq_region,
  drop column if exists hq_country,
  drop column if exists hq_source_url,
  drop column if exists hq_source_level,
  drop column if exists hq_source_date;

drop function if exists public._route_hq_record(uuid, text);
drop function if exists public._hq_home_guard();
drop function if exists public._check8_outside_us(uuid);
drop function if exists public._hq_entry_problem(text, jsonb, jsonb, text);
drop function if exists public._hq_pick_source(uuid, text, jsonb, text);
drop function if exists public._place_hq_item(uuid, jsonb, text, text);
drop function if exists public._place_hq(uuid, text, text, text, text, date);
drop function if exists public._hq_parts(jsonb);
drop function if exists public._hq_source_level(uuid, text, text);
drop function if exists public._hq_trusted(text);
drop function if exists public._hq_register(text);
drop function if exists public._hq_iso(text);
drop function if exists public._hq_label(text);
