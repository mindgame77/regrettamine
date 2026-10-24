-- Tester fix: a political-ties record that keeps its content in value.text (e.g. a lobbying disclosure) showed as
-- 'Untitled record'. check_findings now reads value.text as the note, the kind ('Lobbying') as the title and as_of as
-- the year. Same records counted as before; raw submissions unchanged.
create or replace function public.check_findings(p_sub bigint)
returns table (k int, title text, yr text, status text, note text, who text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare p jsonb;
begin
  if p_sub is null then return; end if;
  select s.payload into p from research_submissions s where s.id = p_sub and s.valid;
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
      from lnk where cn <> 8 and _ck_finding(r) and public._rec_tier(p_sub, r) <> 'needs_source')
  select fnd.k,
         coalesce(v->>'caption', v->>'regulator', case when v->>'kind' = 'donation' then nullif(concat_ws(' → ', v->>'donor', v->>'recipient'), '') end,
                  v->>'list', v->>'title', v->>'name',
                  case when v ? 'theme' then initcap(replace(split_part(v->>'theme', '.', 2), '_', ' ')) end,
                  v->'subject'->>'name',
                  case when nullif(v->>'text', '') is not null then initcap(replace(nullif(v->>'kind', ''), '_', ' ')) end)::text,
         left(coalesce(v->>'filed_at', v->>'date', v->>'event_date', v->>'cycle', v->>'first_reported', case when v ? 'text' then fnd.r->>'as_of' end), 4)::text,
         nullif(nullif(v->>'status', ''), 'unknown')::text,
         coalesce(v->>'summary', v->>'allegation', v->>'note', v->>'text')::text,
         case when fnd.r->>'checklist_item' ~* ' x partner' and v->>'kind' is distinct from 'donation' then coalesce(v->>'donor', v->'subject'->>'name') end::text
    from fnd cross join lateral (select coalesce(fnd.r->'value', '{}') v) x;
end $$;

revoke all on function public.check_findings(bigint) from public, anon, authenticated;
