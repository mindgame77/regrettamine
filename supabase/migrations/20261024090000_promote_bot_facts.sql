-- Promote bot raw facts (research_submissions.payload records) into curated hero facts (firm_profile_facts).
-- Display only: raw submissions are read, never modified. Rows from the spreadsheet loader / other importers
-- (origin is null) are never overwritten; a hero kind a firm already has is skipped.
-- Idempotent: deterministic ids, latest valid submission wins, rerun = same result.

alter table public.firm_profile_facts add column if not exists origin text;  -- null = loader/importer; 'promoted from submission N'

create or replace function public._promo_money(v jsonb) returns text language sql immutable as $$
  select case
    when jsonb_typeof(v->'amount_usd') = 'number' and (v->>'amount_usd')::numeric >= 1e9 then '$' || trim(to_char((v->>'amount_usd')::numeric / 1e9, 'FM999990.0')) || 'B'
    when jsonb_typeof(v->'amount_usd') = 'number' and (v->>'amount_usd')::numeric > 0 then '$' || trim(to_char((v->>'amount_usd')::numeric / 1e6, 'FM999990')) || 'M'
    else substring(coalesce(v->>'press_aum', v->>'regulatory_aum', '') from '~?>?\$[0-9.,]+ ?[BMK]')
  end $$;

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
       and exists (select 1 from jsonb_array_elements(coalesce(r->'sources', '[]')) x where coalesce(x->>'url', '') like 'http%')
     order by s.received_at desc, s.id desc limit 1;
    continue when rec.sub is null;
    if k.fp = 'hq' then
      hv := coalesce(rec.r->'value'->>'city', rec.r->>'value'); v := coalesce(rec.r->'value'->>'address', hv);
    else
      hv := _promo_money(rec.r->'value'); v := hv || coalesce(' · ' || (rec.r->'value'->>'basis'), '');
    end if;
    continue when nullif(trim(hv), '') is null;
    fid := md5('promoted:' || p_firm || ':' || k.fp)::uuid;
    insert into firm_profile_facts(id, firm_id, section, label, value, hero_label, hero_value, sort_order, origin)
    values (fid, p_firm, k.sec, k.lbl, left(v, 400), k.hl, left(hv, 60), k.so, 'promoted from submission ' || rec.sub)
    on conflict (id) do update set value = excluded.value, hero_value = excluded.hero_value, origin = excluded.origin
      where firm_profile_facts.origin like 'promoted from submission %';
    delete from fact_sources where fact_type = 'firm_profile_facts' and fact_id = fid;
    i := 0;
    for src in select x from jsonb_array_elements(rec.r->'sources') x where coalesce(x->>'url', '') like 'http%' loop
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
revoke all on function public.promote_bot_facts(uuid) from public, anon, authenticated;

create or replace function public.promote_bot_facts_trg() returns trigger
language plpgsql security definer set search_path = public as $$
declare f uuid;
begin
  if not new.valid then return null; end if;
  for f in select id from firms where deleted_at is null and _firm_queue_id(id) = new.registry_id loop
    begin
      perform promote_bot_facts(f);
    exception when others then
      raise warning 'promote_bot_facts: submission % firm %: %', new.id, f, sqlerrm;  -- never block an ingest
    end;
  end loop;
  return null;
end $$;

revoke all on function public.promote_bot_facts_trg() from public, anon, authenticated;

drop trigger if exists promote_bot_facts on public.research_submissions;
create trigger promote_bot_facts after insert on public.research_submissions
  for each row execute function public.promote_bot_facts_trg();

-- Backfill every published bot firm.
select promote_bot_facts(id) from firms
 where published and deleted_at is null and not coalesce(is_test, false) and data_status = 'real' and _firm_queue_id(id) is not null;

-- Queue: add Sequoia Capital (CRD 157373) and move it + General Catalyst, Lightspeed, Plug and Play to the front.
insert into research_queue(registry_id, name, country, state, hq_city, sec_crd, priority, firm_type, type_source)
select 'vc-' || lpad((max(substring(registry_id from 4)::int) + 1)::text, 6, '0'), 'Sequoia Capital', 'United States', 'CA', 'Menlo Park', '157373', 0, 'vc', 'sec_adv_crd'
  from research_queue where registry_id ~ '^vc-[0-9]+$'
having not exists (select 1 from research_queue where sec_crd = '157373');
with front as (select min(priority) m from research_queue where status = 'queued' and coalesce(sec_crd, '') not in ('157373', '162548', '160187', '321635')),
     tgt as (select registry_id, row_number() over (order by case sec_crd when '157373' then 0 when '162548' then 1 when '160187' then 2 else 3 end) rn
               from research_queue where sec_crd in ('157373', '162548', '160187', '321635') and status = 'queued')
update research_queue q set priority = front.m - 5 + tgt.rn, bumped_at = now(), updated_at = now()
  from front, tgt where q.registry_id = tgt.registry_id
   and exists (select 1 from research_queue o where o.status = 'queued' and o.priority <= q.priority
                and coalesce(o.sec_crd, '') not in ('157373', '162548', '160187', '321635'));  -- already at the front: no-op
