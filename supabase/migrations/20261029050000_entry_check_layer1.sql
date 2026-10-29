-- Entry check, Layer 1 (step A of the approved 'entry check' plan; Alex, 2026-10-28; rules A4.6, A4.7).
-- Instant database checks on every row a bot uploads into bots.research_submissions (the holding door, A3.1).
-- Each new row gets entry_check = 'Accepted' or 'Rejected: <reason>[; <reason>...]', plus internal entry_notes from
-- fix-ups that never reject: dates normalized (unreadable ones cleared) and items past the A9 limit archived.
-- Internal only, never shown;
-- the result is cleared after 30 days (bots.entry_check_purge, A4.6).
-- This does NOT publish anything and does NOT turn the 10 checks back on (20261029031000_checks_off stays).
-- Not possible inside a trigger: opening the link over HTTP. Rows get entry_link_open_pending = true so the Checker
-- (or a later job) does the real 'opens' check (A5.2).
-- Reuses: public._checker_payload_items (both payload shapes), public._checker_url_key (A7.11 news key),
-- public._dom / public._checker_host, public._src_search_page (A1.7), public._door_key (A4.3 exact copy),
-- bots.apply_limits (local timeouts). Grants follow A14.6: fixed search_path, no EXECUTE for public/anon/authenticated.
-- Rollback: supabase/rollbacks/20261029050000_entry_check_layer1.sql

alter table bots.research_submissions
  add column if not exists entry_check text,
  add column if not exists entry_check_at timestamptz,
  add column if not exists entry_link_open_pending boolean,
  add column if not exists entry_notes text[];
comment on column bots.research_submissions.entry_notes is
  'A4.7 internal notes from the fix-ups (e.g. 1 date unreadable, cleared; 3 items over the A9 limit archived). Never shown. Cleared after 30 days.';
comment on column bots.research_submissions.entry_check is
  'A4.6 door-check result: Accepted or Rejected: <reason>. Internal only, never shown. Cleared after 30 days.';
comment on column bots.research_submissions.entry_link_open_pending is
  'A4.7: true until the Checker or a later job confirms the links open (HTTP cannot run inside a trigger).';

-- Fixed word lists (A2.4). Applied to legal items only (other lists use 'status' for other things).
create or replace function public._entry_status_bad(p_f jsonb)
 returns text language sql immutable set search_path = public, extensions as $$
  select case
    when jsonb_typeof(p_f) <> 'object' then null
    when nullif(btrim(coalesce(p_f->>'status', p_f->>'legal_status', p_f->>'lawsuit_status', '')), '') is not null
     and initcap(btrim(coalesce(p_f->>'status', p_f->>'legal_status', p_f->>'lawsuit_status'))) not in ('Active', 'Closed', 'Settled', 'Dismissed')
      then 'status word not on the fixed list (Active, Closed, Settled, Dismissed)'
    when nullif(btrim(coalesce(p_f->>'side', '')), '') is not null
     and initcap(btrim(p_f->>'side')) not in ('Defendant', 'Plaintiff')
      then 'side word not on the fixed list (Defendant, Plaintiff)'
    when nullif(btrim(coalesce(p_f->>'about', p_f->>'case_type', '')), '') is not null
     and lower(btrim(coalesce(p_f->>'about', p_f->>'case_type')))
         not in ('fraud', 'contract', 'employment', 'securities', 'regulator action', 'ip')
      then 'case type not on the fixed list (Fraud, Contract, Employment, Securities, Regulator action, IP)'
    end $$;

-- Date normalization (A13.2; Alex 2026-10-28: a bad date never rejects an item). Returns YYYY-MM-DD, YYYY-MM or
-- YYYY, or null when the text can't be read. Handles ISO dates and timestamps, MM/DD/YYYY, 'Oct 5, 2026',
-- '5 October 2026', 'October 2026', 'Oct 2026'.
create or replace function public._entry_norm_date(p text)
 returns text language plpgsql immutable set search_path = public, extensions as $$
declare t text := btrim(regexp_replace(coalesce(p, ''), '\s+', ' ', 'g')); m text[];
begin
  if t = '' then return null; end if;
  if t ~ '^\d{4}$' then return t; end if;
  if t ~ '^\d{4}-\d{1,2}$' then
    m := regexp_match(t, '^(\d{4})-(\d{1,2})$');
    return to_char(make_date(m[1]::int, m[2]::int, 1), 'YYYY-MM');
  end if;
  m := regexp_match(t, '^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})([T ].*)?$');
  if m is not null then return to_char(make_date(m[1]::int, m[2]::int, m[3]::int), 'YYYY-MM-DD'); end if;
  m := regexp_match(t, '^(\d{1,2})/(\d{1,2})/(\d{4})$');  -- US MM/DD/YYYY (A13.1)
  if m is not null then return to_char(make_date(m[3]::int, m[1]::int, m[2]::int), 'YYYY-MM-DD'); end if;
  m := regexp_match(t, '^([A-Za-z]{3,9})\.? (\d{1,2})(st|nd|rd|th)?,? (\d{4})$');  -- Oct 5, 2026
  if m is not null then return to_char(to_date(left(m[1], 3) || ' ' || m[2] || ' ' || m[4], 'Mon DD YYYY'), 'YYYY-MM-DD'); end if;
  m := regexp_match(t, '^(\d{1,2})(st|nd|rd|th)? ([A-Za-z]{3,9})\.?,? (\d{4})$');  -- 5 October 2026
  if m is not null then return to_char(to_date(left(m[3], 3) || ' ' || m[1] || ' ' || m[4], 'Mon DD YYYY'), 'YYYY-MM-DD'); end if;
  m := regexp_match(t, '^([A-Za-z]{3,9})\.?,? (\d{4})$');  -- October 2026
  if m is not null then return to_char(to_date(left(m[1], 3) || ' 1 ' || m[2], 'Mon DD YYYY'), 'YYYY-MM'); end if;
  return null;
exception when others then return null;
end $$;

-- Is this key a date field? (as_of, published_at, date, filed, closed, *_date, *_at, *_on)
create or replace function public._entry_is_date_key(k text)
 returns boolean language sql immutable set search_path = public, extensions as $$
  select coalesce(k, '') ~* '^(as_of|date|filed|closed)$|_(date|at|on)$' $$;

-- Normalize every date field in one object. Unreadable dates become null; o_cleared counts them.
create or replace function public._entry_fix_dates(p_obj jsonb, out o_obj jsonb, out o_cleared int)
 language plpgsql immutable set search_path = public, extensions as $$
declare e record; v text;
begin
  o_obj := p_obj; o_cleared := 0;
  if jsonb_typeof(p_obj) <> 'object' then return; end if;
  for e in select key, value from jsonb_each(p_obj) where jsonb_typeof(value) = 'string' and public._entry_is_date_key(key) loop
    v := public._entry_norm_date(e.value #>> '{}');
    if v is null then
      if btrim(e.value #>> '{}') <> '' then o_cleared := o_cleared + 1; end if;
      o_obj := jsonb_set(o_obj, array[e.key], 'null'::jsonb);
    elsif v is distinct from e.value #>> '{}' then
      o_obj := jsonb_set(o_obj, array[e.key], to_jsonb(v));
    end if;
  end loop;
end $$;

-- Fix-ups that never reject (Alex 2026-10-28): normalize dates (checks 4) and archive items past the A9 limit
-- (check 6). Returns {"payload": <fixed payload>, "notes": [internal notes]}. Items past the limit keep their place
-- in the upload with "archived": true (kept, hidden, never deleted; A9.1). The first items up to the limit are kept.
create or replace function public._entry_fix_payload(p jsonb)
 returns jsonb language plpgsql stable set search_path = public, extensions as $$
declare
  caps jsonb := '{"people":20,"press":50,"news":50,"timeline":50,"founders":50,"deals":1000,"funds":100,"lps":100,"legal":100,"interviews":10}';
  out_p jsonb := p; recs jsonb; rec jsonb; i int; sec text; cnt jsonb := '{}'; arch int := 0; cleared int := 0;
  fx record; src jsonb; k text; j int; arr jsonb; notes text[] := '{}';
begin
  if p is null or jsonb_typeof(p) <> 'object' then return jsonb_build_object('payload', p, 'notes', '[]'::jsonb); end if;
  if jsonb_typeof(p->'records') = 'array' then
    recs := p->'records';
    for i in 0 .. jsonb_array_length(recs) - 1 loop
      rec := recs->i;
      if jsonb_typeof(rec) <> 'object' then continue; end if;
      select * into fx from public._entry_fix_dates(rec); rec := fx.o_obj; cleared := cleared + fx.o_cleared;
      if jsonb_typeof(rec->'value') = 'object' then
        select * into fx from public._entry_fix_dates(rec->'value'); rec := jsonb_set(rec, '{value}', fx.o_obj); cleared := cleared + fx.o_cleared;
      end if;
      if jsonb_typeof(rec->'sources') = 'array' then
        src := '[]';
        for j in 0 .. jsonb_array_length(rec->'sources') - 1 loop
          select * into fx from public._entry_fix_dates(rec->'sources'->j); src := src || jsonb_build_array(fx.o_obj); cleared := cleared + fx.o_cleared;
        end loop;
        rec := jsonb_set(rec, '{sources}', src);
      end if;
      sec := public._entry_section(case rec->>'field_path'
          when 'people' then 'people' when 'peopleMoves' then 'people' when 'funds' then 'funds' when 'latestRaise' then 'funds'
          when 'limitedPartners' then 'lps' when 'portfolio' then 'deals' when 'lawsuits' then 'legal'
          when 'regulatoryActions' then 'legal' when 'sanctions' then 'legal' when 'controversies' then 'legal'
          when 'posts' then 'founders' when 'reviews' then 'founders' else 'overview' end, rec->>'field_path');
      cnt := jsonb_set(cnt, array[sec], to_jsonb(coalesce((cnt->>sec)::int, 0) + 1));
      if caps ? sec and (cnt->>sec)::int > (caps->>sec)::int then rec := rec || '{"archived": true}'; arch := arch + 1; end if;
      recs := jsonb_set(recs, array[i::text], rec);
    end loop;
    out_p := jsonb_set(out_p, '{records}', recs);
  end if;
  if jsonb_typeof(p->'sections') = 'object' then
    for k in select jsonb_object_keys(p->'sections') loop
      arr := out_p->'sections'->k;
      if jsonb_typeof(arr) <> 'array' then continue; end if;
      sec := public._entry_section(k, k);
      for j in 0 .. jsonb_array_length(arr) - 1 loop
        select * into fx from public._entry_fix_dates(arr->j); cleared := cleared + fx.o_cleared;
        if caps ? sec and j + 1 > (caps->>sec)::int and jsonb_typeof(fx.o_obj) = 'object' then
          fx.o_obj := fx.o_obj || '{"archived": true}'; arch := arch + 1;
        end if;
        arr := jsonb_set(arr, array[j::text], fx.o_obj);
      end loop;
      out_p := jsonb_set(out_p, array['sections', k], arr);
    end loop;
  end if;
  if cleared > 0 then notes := notes || format('%s date%s unreadable, cleared', cleared, case when cleared > 1 then 's' else '' end); end if;
  if arch > 0 then notes := notes || format('%s item%s over the A9 limit archived', arch, case when arch > 1 then 's' else '' end); end if;
  return jsonb_build_object('payload', out_p, 'notes', to_jsonb(notes));
end $$;

-- Source level 1-3 (A1): an explicit source_level / level, or the bot tier T1-T3.
create or replace function public._entry_level(p_rec jsonb, p_f jsonb)
 returns integer language sql immutable set search_path = public, extensions as $$
  select coalesce(
    case when coalesce(p_f->>'source_level', p_rec->>'source_level') ~ '^\d+$'
         then coalesce(p_f->>'source_level', p_rec->>'source_level')::int end,
    case when coalesce(p_rec->'sources'->0->>'tier', p_f->>'tier', '') ~* '^T?\d+$'
         then regexp_replace(coalesce(p_rec->'sources'->0->>'tier', p_f->>'tier'), '\D', '', 'g')::int end) $$;

-- List name for an item: the reused section, but news/press records (records shape) map to 'press'.
create or replace function public._entry_section(p_section text, p_field_path text)
 returns text language sql immutable set search_path = public, extensions as $$
  select case when lower(coalesce(p_field_path, '')) in ('press', 'news', 'timeline', 'articles', 'media') then 'press'
              when lower(coalesce(p_field_path, '')) = 'interviews' then 'interviews'
              else p_section end $$;

-- Rejecting checks 1, 2, 5, 7 (and the A9.19 thesis length) on one payload. p_firm_dom is the firm's own domain (for check 7).
create or replace function public._entry_check_reasons(p jsonb, p_firm_dom text)
 returns text[] language plpgsql stable set search_path = public, extensions as $$
declare
  r text[] := '{}';
  it record; recs jsonb; rec jsonb; lvl int; sec text;
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
    lvl := case when it.n = 0 then 2 else public._entry_level(rec, it.f) end;  -- n = 0: the firm's own website item
    if lvl is null then r := r || 'no source level'::text;
    elsif lvl not between 1 and 3 then r := r || ('source level ' || lvl || ' is not 1 to 3')::text;
    end if;
    -- 4) dates: never rejected; normalized or cleared by _entry_fix_payload.
    -- 5) status words
    if it.section = 'legal' and public._entry_status_bad(it.f) is not null then r := r || public._entry_status_bad(it.f); end if;
    -- 6b) thesis max 1,000 characters (A9.19)
    if lower(coalesce(it.f->>'label', rec->>'field_path', '')) = 'thesis'
       and length(coalesce(it.f->>'value', '')) > 1000 then
      r := r || 'thesis over 1,000 characters (A9.19)'::text;
    end if;
    -- 7) no news from the firm's own site
    if sec in ('press', 'news', 'timeline') and dom is not null and it.url is not null
       and (public._dom(it.url) = dom or public._dom(it.url) like '%.' || dom) then
      r := r || 'news item from the firm''s own website or blog'::text;
    end if;
  end loop;

  -- 6) A9 list limits: never rejected; extra items archived by _entry_fix_payload.

  return (select coalesce(array_agg(x order by o), '{}') from (select x, min(o) o from unnest(r) with ordinality u(x, o) group by x) s);
end $$;

-- 3) duplicate of an existing published or submitted item.
create or replace function public._entry_duplicate(p_id bigint, p_registry text, p_bot text, p jsonb)
 returns text language plpgsql stable security definer set search_path = public, extensions as $$
declare k text := public._door_key(p_registry, p);
begin
  if exists (select 1 from bots.research_submissions s
              where s.id is distinct from p_id
                and coalesce(s.door_key, public._door_key(s.registry_id, s.payload)) = k) then
    return 'duplicate of an earlier upload';
  end if;
  if exists (select 1 from public._checker_payload_items(p) i
              join public.press_items pi on public._checker_url_key(pi.url) = public._checker_url_key(i.url)
             where public._entry_section(i.section, case when i.n >= 1 then p->'records'->(i.n - 1)->>'field_path' end)
                   in ('press', 'news', 'timeline') and i.url is not null) then
    return 'duplicate of a published news item';
  end if;
  if exists (select 1 from public._checker_payload_items(p) i
              where i.url is not null
              group by i.section, public._checker_url_key(i.url), coalesce(i.f->>'value', i.f::text)
             having count(*) > 1) then
    return 'duplicate items inside the upload';
  end if;
  return null;
end $$;

create or replace function public._entry_check(p_id bigint, p_registry text, p_bot text, p jsonb)
 returns text language plpgsql stable security definer set search_path = public, extensions as $$
declare r text[]; dup text; dom text;
begin
  dom := coalesce(nullif(p->'firm'->>'primary_domain', ''),
                  (select f.primary_domain from public.firms f where f.registry_id = p_registry limit 1),
                  public._checker_host(nullif(p->'firm'->>'website', '')));
  r := public._entry_check_reasons(p, dom);
  dup := public._entry_duplicate(p_id, p_registry, p_bot, p);
  if dup is not null then r := r || dup; end if;
  if coalesce(array_length(r, 1), 0) = 0 then return 'Accepted'; end if;
  return 'Rejected: ' || array_to_string(r, '; ');
end $$;

create or replace function bots.entry_check_trg()
 returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare fx jsonb;
begin
  perform bots.apply_limits();
  begin
    -- Duplicate key from the payload as sent, so an exact copy still matches after the fix-ups below.
    new.door_key := coalesce(new.door_key, public._door_key(new.registry_id, new.payload));
    new.entry_check := public._entry_check(new.id, new.registry_id, new.bot_id, new.payload);
    fx := public._entry_fix_payload(new.payload);
    new.payload := fx->'payload';
    new.entry_notes := nullif(array(select jsonb_array_elements_text(fx->'notes')), '{}');
  exception when others then
    new.entry_check := 'Rejected: entry check error';  -- never block the upload itself
  end;
  new.entry_check_at := now();
  new.entry_link_open_pending := (new.entry_check = 'Accepted');
  return new;
end $$;

drop trigger if exists aa_entry_check on bots.research_submissions;
create trigger aa_entry_check before insert on bots.research_submissions
  for each row execute function bots.entry_check_trg();

-- A4.6: keep the result 30 days.
create or replace function bots.entry_check_purge()
 returns integer language plpgsql security definer set search_path = public, extensions as $$
declare n integer;
begin
  update bots.research_submissions set entry_check = null, entry_link_open_pending = null, entry_notes = null
   where entry_check is not null and entry_check_at < now() - interval '30 days';
  get diagnostics n = row_count;
  return n;
end $$;

-- A14.6 grants: server only.
revoke all on function public._entry_section(text, text) from public, anon, authenticated;
revoke all on function public._entry_status_bad(jsonb) from public, anon, authenticated;
revoke all on function public._entry_norm_date(text) from public, anon, authenticated;
revoke all on function public._entry_is_date_key(text) from public, anon, authenticated;
revoke all on function public._entry_fix_dates(jsonb) from public, anon, authenticated;
revoke all on function public._entry_fix_payload(jsonb) from public, anon, authenticated;
revoke all on function public._entry_level(jsonb, jsonb) from public, anon, authenticated;
revoke all on function public._entry_check_reasons(jsonb, text) from public, anon, authenticated;
revoke all on function public._entry_duplicate(bigint, text, text, jsonb) from public, anon, authenticated;
revoke all on function public._entry_check(bigint, text, text, jsonb) from public, anon, authenticated;
revoke all on function bots.entry_check_trg() from public, anon, authenticated;
revoke all on function bots.entry_check_purge() from public, anon, authenticated;
grant execute on function bots.entry_check_purge() to service_role;
