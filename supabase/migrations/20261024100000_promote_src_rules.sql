-- Promotion fix (tester, Oct 23): only cite the record's own press/SEC sources. Government pages other than SEC
-- (e.g. a U.S. embassy bio) are not promoted; an AUM card whose figure has no cited source (press_aum text) is hidden.
-- Only rows this step created (origin 'promoted from submission N') are ever removed; raw submissions untouched.
create or replace function public._promo_src_ok(u text) returns boolean language sql immutable as $$
  select coalesce(substring(lower(u) from '://(?:www\.)?([^/:]+)'), '') !~ '(embassy|\.gov$|\.gov\.[a-z]+$|\.mil$)'
      or coalesce(substring(lower(u) from '://(?:www\.)?([^/:]+)'), '') ~ '(^|\.)sec\.gov$' $$;

create or replace function public.promote_bot_facts(p_firm uuid) returns int
language plpgsql security definer set search_path = public as $$
declare qid text := _firm_queue_id(p_firm); k record; rec record; fid uuid; n int := 0;
  hv text; v text; src jsonb; sid uuid; i int;
begin
  if qid is null then return 0; end if;
  for k in select * from (values ('hq', 'overview', 'Headquarters', 'HQ', array['HQ'], 0),
                                 ('aum', 'funds', 'Assets under management', 'Assets', array['Assets', 'Regulatory AUM', 'AUM'], 0)) t(fp, sec, lbl, hl, same, so) loop
    -- never compete with a curated (non-promoted) card of the same kind
    continue when exists (select 1 from firm_profile_facts where firm_id = p_firm and hero_label = any(k.same) and origin is null);
    select s.id sub, r.value r into rec from research_submissions s, jsonb_array_elements(coalesce(s.payload->'records', '[]')) r
     where s.registry_id = qid and s.valid and r->>'field_path' = k.fp
       and exists (select 1 from jsonb_array_elements(coalesce(r->'sources', '[]')) x where coalesce(x->>'url', '') like 'http%' and public._promo_src_ok(x->>'url'))
     order by s.received_at desc, s.id desc limit 1;
    fid := md5('promoted:' || p_firm || ':' || k.fp)::uuid;
    if rec.sub is null then delete from firm_profile_facts where id = fid and origin like 'promoted from submission %' and origin is not null; delete from fact_sources where fact_type = 'firm_profile_facts' and fact_id = fid and not exists (select 1 from firm_profile_facts where id = fid); continue; end if;
    if k.fp = 'hq' then
      hv := coalesce(rec.r->'value'->>'city', rec.r->>'value'); v := coalesce(rec.r->'value'->>'address', hv);
    else
      hv := case when jsonb_typeof(rec.r->'value'->'amount_usd') = 'number' then _promo_money(rec.r->'value') end;  -- press_aum text has no cited URL: hide
      v := hv || coalesce(' · ' || (rec.r->'value'->>'basis'), '');
    end if;
    if nullif(trim(hv), '') is null then delete from firm_profile_facts where id = fid and origin like 'promoted from submission %' and origin is not null; delete from fact_sources where fact_type = 'firm_profile_facts' and fact_id = fid and not exists (select 1 from firm_profile_facts where id = fid); continue; end if;
    insert into firm_profile_facts(id, firm_id, section, label, value, hero_label, hero_value, sort_order, origin)
    values (fid, p_firm, k.sec, k.lbl, left(v, 400), k.hl, left(hv, 60), k.so, 'promoted from submission ' || rec.sub)
    on conflict (id) do update set value = excluded.value, hero_value = excluded.hero_value, origin = excluded.origin
      where firm_profile_facts.origin like 'promoted from submission %';
    delete from fact_sources where fact_type = 'firm_profile_facts' and fact_id = fid;
    i := 0;
    for src in select x from jsonb_array_elements(rec.r->'sources') x where coalesce(x->>'url', '') like 'http%' and public._promo_src_ok(x->>'url') loop
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
  return n;
end $$;
grant execute on function public.promote_bot_facts(uuid) to service_role;

select promote_bot_facts(id) from firms
 where published and deleted_at is null and not coalesce(is_test, false) and data_status = 'real' and _firm_queue_id(id) is not null;
