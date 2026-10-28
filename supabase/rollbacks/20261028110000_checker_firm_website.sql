-- Puts the submission reader back to sections and records only.
-- Does not turn the Checker off and does not clear a primary_domain already saved.

drop function if exists public.checker_publish_submission(bigint, jsonb);

create or replace function public._checker_payload_items(p jsonb)
returns table(n int, section text, f jsonb, url text)
language plpgsql stable as $$
begin
  if jsonb_typeof(p->'sections') = 'object' then
    return query select c.n, c.section, c.f, c.url from public.checked_items(p) c where c.outcome = 'ok';
    return;
  end if;
  if jsonb_typeof(p->'records') = 'array' then
    return query
    select s.n::int, s.section, s.f, s.url from (
      select row_number() over () n,
        case r->>'field_path'
          when 'people' then 'people' when 'peopleMoves' then 'people'
          when 'funds' then 'funds' when 'latestRaise' then 'funds'
          when 'limitedPartners' then 'lps' when 'portfolio' then 'deals'
          when 'lawsuits' then 'legal' when 'regulatoryActions' then 'legal'
          when 'sanctions' then 'legal' when 'controversies' then 'legal'
          when 'posts' then 'founders' when 'reviews' then 'founders'
          else 'overview' end section,
        case when jsonb_typeof(r->'value') = 'object' then r->'value'
             else jsonb_build_object('label', r->>'field_path', 'value', r->>'value') end f,
        (select x->>'url' from jsonb_array_elements(case when jsonb_typeof(r->'sources') = 'array' then r->'sources' else '[]'::jsonb end) x limit 1) url
      from jsonb_array_elements(p->'records') r
    ) s;
  end if;
end $$;

create or replace function public.checker_publish_submission(p_id bigint) returns jsonb
language plpgsql security definer set search_path = bots, public as $$
declare sub bots.research_submissions; fid uuid; it record; lvl smallint; ncheck int; outcome text; reason text;
  pub int := 0; skip int := 0; fail int := 0; unconf int := 0; merged int := 0; noted int := 0;
begin
  select * into sub from research_submissions where id = p_id;
  if sub.id is null or not public._checker_publish_on() then
    return jsonb_build_object('ran', false);
  end if;
  select f.id into fid from firms f
   where f.deleted_at is null and f.registry_id = coalesce(public._registry_target(sub.registry_id), sub.registry_id)
   order by f.published desc limit 1;
  if fid is null or not public._lab_firm(fid) then
    return jsonb_build_object('ran', false, 'reason', 'not a lab firm');
  end if;
  for it in select * from public._checker_payload_items(sub.payload) loop
    begin
      ncheck := public._checker_check_n(it.section, it.url);
      select d.lvl, d.outcome, d.reason into lvl, outcome, reason
        from public._checker_decide(fid, it.section, it.f, it.url, ncheck, null) d;
      if outcome = 'published' then
        select p.outcome, p.reason into outcome, reason
          from public._checker_place(fid, it.section, it.f, it.url, lvl, ncheck, sub.id) p;
      end if;
    exception when others then
      outcome := 'failure'; reason := sqlerrm;
    end;
    if outcome = 'published' then pub := pub + 1;
    elsif outcome = 'merged' then merged := merged + 1;
    elsif outcome = 'note' then noted := noted + 1;
    elsif outcome = 'skipped' then skip := skip + 1;
    elsif outcome = 'unconfirmed' then unconf := unconf + 1;
    else fail := fail + 1; end if;
    if outcome in ('failure', 'unconfirmed') then
      insert into checker_holding(firm_id, origin, origin_id, kind, url, outcome, reason, item)
      values (fid, 'submission', sub.id, it.section, it.url,
              case when outcome = 'unconfirmed' then 'unconfirmed' else 'failure' end, reason, it.f);
    end if;
  end loop;
  return jsonb_build_object('ran', true, 'firm_id', fid, 'published', pub, 'merged', merged, 'note', noted,
    'skipped', skip, 'unconfirmed', unconf, 'failure', fail);
end $$;
revoke all on function public.checker_publish_submission(bigint) from public, anon, authenticated;

drop function if exists public._checker_link_opens(text, jsonb);
drop function if exists public._checker_host(text);
