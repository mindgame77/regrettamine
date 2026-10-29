-- Rollback of 20261029110000_upload_fields_legal_words.sql: restores the two helpers exactly as they were live
-- before the change. Edge function: redeploy supabase/rollbacks/20261029110000_research_ingest_v31.ts as research-ingest (verify_jwt false).
CREATE OR REPLACE FUNCTION public._entry_status_bad(p_f jsonb)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'extensions'
AS $function$
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
    end $function$
;

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
    -- 6b) thesis over 1,000 characters (A9.19): never rejected; cut by _entry_fix_payload.
    -- 7) no news from the firm's own site
    if sec in ('press', 'news', 'timeline') and dom is not null and it.url is not null
       and (public._dom(it.url) = dom or public._dom(it.url) like '%.' || dom) then
      r := r || 'news item from the firm''s own website or blog'::text;
    end if;
  end loop;

  -- 6) A9 list limits: never rejected; extra items archived by _entry_fix_payload.

  return (select coalesce(array_agg(x order by o), '{}') from (select x, min(o) o from unnest(r) with ordinality u(x, o) group by x) s);
end $function$
;

revoke all on function public._entry_status_bad(jsonb) from public, anon, authenticated;
revoke all on function public._entry_check_reasons(jsonb, text) from public, anon, authenticated;
