-- Regretamin launch: details payload after unlock + anonymous free-check cap per IP hash. Additive.
-- Replaces only functions created by 20261022120000_launch_checks.sql.

alter table public.check_events add column if not exists ip_hash text;
create index if not exists check_events_ip on public.check_events(ip_hash, created_at) where ip_hash is not null;

-- Raw sourced facts per check row (1-10). real + needs_proof, never test. Different-person name-only hits dropped.
-- Newest row per case (same row + case key keeps the most recent retrieved_at).
create or replace function public.firm_details(p_firm uuid) returns json
language sql stable security definer set search_path = public as $$
  with f as (
    select x.*, x.value->>'field' fld,
      case when jsonb_typeof(x.value) = 'object' then x.value else jsonb_build_object('value', x.value) end v
    from vc_source_facts x
    where x.firm_id = p_firm and x.superseded_by is null and x.data_status::text in ('real','needs_proof')
      and x.value::text !~* '(different (person|people)|surname-only|name-only hit|name-order variant|not treated as a match|similar name)'
  ), r as (
    select f.*, case
      when fact_type = 'sanctions_check' and (fld in ('sanctions','sanctions_check') or v ? 'result') then 1
      when fld = 'terrorism_lists' then 2
      when fld = 'export_restrictions' then 3
      when fact_type = 'regulatory_record' and fld like 'regulatory_action%' or fld = 'sec_disciplinary'
        or (fact_type = 'legal_matter' and v->>'title' like '%DOJ%') then 4
      when fld in ('aml_penalties','adv_disclosures') then 5
      when fld = 'courts_worldwide' then 7
      when fld in ('registration_status','legal_entity') or fact_type in ('sec_crd','legal_entity') then 8
      when fld = 'people_screen' or (fact_type = 'legal_matter' and v->>'entity' like 'partner:%') then 9
      when fact_type = 'legal_matter' and (v ? 'title' or fld = 'legal_matter') then 6
      when fld = 'pep' then 10
    end rn,
    coalesce(v->>'title', v->>'value',
      case when v ? 'result' then 'Result: ' || replace(v->>'result','_',' ') || coalesce(' on ' || (select string_agg(e, ', ') from jsonb_array_elements_text(v->'lists') e), '')
        || coalesce(' · ' || (v->>'people_checked') || ' people checked', '') end,
      v::text) txt
    from f
  ), d as (
    select distinct on (rn, coalesce(v->>'detail', md5(txt))) * from r where rn is not null
    order by rn, coalesce(v->>'detail', md5(txt)), retrieved_at desc nulls last
  )
  select coalesce(json_agg(json_build_object('row', rn, 'facts', facts) order by rn), '[]'::json) from (
    select rn, json_agg(json_build_object('text', txt, 'case', v->>'detail', 'year', v->>'year', 'who', v->>'entity',
      'needs_proof', data_status::text = 'needs_proof', 'url', source_url, 'label', coalesce(source_label, v->>'publisher'),
      'date', to_char(retrieved_at, 'Mon FMDD, YYYY')) order by data_status::text, (v->>'year') desc nulls last, retrieved_at desc) facts
    from d group by rn) g
$$;
revoke all on function public.firm_details(uuid) from public, anon, authenticated;

create or replace function public._ip_hash() returns text
language sql stable set search_path = public as $$
  select case when ip is null or ip = '' then null else encode(extensions.digest('regretamin:' || ip, 'sha256'), 'hex') end
  from (select trim(split_part(coalesce(current_setting('request.headers', true)::json->>'x-forwarded-for', ''), ',', 1)) ip) s
$$;
revoke all on function public._ip_hash() from public, anon, authenticated;

-- Same as before, plus: anonymous free spends capped at 4 per IP hash per 30 days (then sign-up modal).
create or replace function public.unlock_firm(p_slug text, p_anon uuid, p_spend boolean default true) returns json
language plpgsql security definer set search_path = public as $$
declare b public.check_balances := _balance(p_anon); f uuid; h text := _ip_hash(); ip_cap constant int := 4;
begin
  select id into f from firms where slug = p_slug and deleted_at is null and published;
  if f is null then return json_build_object('status','not_found'); end if;
  if not exists (select 1 from check_events where balance_id = b.id and firm_id = f and kind like 'spend_%') then
    if not p_spend then return json_build_object('status','locked'); end if;
    if b.free_left > 0 and auth.uid() is null and h is not null
       and (select count(*) from check_events where ip_hash = h and kind = 'spend_free' and created_at > now() - interval '30 days') >= ip_cap then
      return json_build_object('status','need_signup');
    end if;
    if b.free_left > 0 then
      update check_balances set free_left = free_left - 1, updated_at = now() where id = b.id;
      insert into check_events(balance_id, firm_id, kind, amount, ip_hash) values (b.id, f, 'spend_free', -1, case when auth.uid() is null then h end);
    elsif b.paid_left > 0 then
      update check_balances set paid_left = paid_left - 1, updated_at = now() where id = b.id;
      insert into check_events(balance_id, firm_id, kind, amount) values (b.id, f, 'spend_paid', -1);
    elsif auth.uid() is null then return json_build_object('status','need_signup');
    else return json_build_object('status','out');
    end if;
  end if;
  return json_build_object('status','ok','details', public.firm_details(f));
end $$;
grant execute on function public.unlock_firm(text,uuid,boolean) to anon, authenticated;

-- For the notify worker (service role only): queued requests whose firm is now published.
create or replace function public.ready_check_requests() returns table(id bigint, email text, query text, slug text, name text)
language sql stable security definer set search_path = public as $$
  select r.id, r.email, r.query, f.slug, f.name
  from check_requests r
  join lateral (
    select fm.* from firms fm
    where fm.published and fm.deleted_at is null and (
      fm.id = r.firm_id or lower(fm.name) = lower(trim(r.query)) or lower(fm.slug) = lower(trim(r.query))
      or lower(coalesce(fm.short_name,'')) = lower(trim(r.query))
      or exists (select 1 from vc_aliases a where a.firm_id = fm.id and lower(a.value) = lower(trim(r.query))))
    order by (fm.id = r.firm_id) desc limit 1) f on true
  where r.email is not null and r.notified_at is null and r.status in ('queued','running','done')
  order by r.created_at limit 50
$$;
revoke all on function public.ready_check_requests() from public, anon, authenticated;
grant execute on function public.ready_check_requests() to service_role;

-- Fix: the Stripe webhook runs as service_role and must be able to call grant_checks.
grant execute on function public.grant_checks(uuid,text,int,text,text,timestamptz,text,text) to service_role;
