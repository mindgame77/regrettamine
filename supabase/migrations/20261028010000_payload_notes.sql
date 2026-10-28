-- Top-level payload.notes (a string, or each string in an array) is outcome 'note'.
-- The current checker stays, including _data_rule. Top-level notes are saved on
-- publish_checks only for the 10 lab firms, or a slug listed in ingest_settings.lab_firm_slugs.
-- Notes are never published. Nothing is deleted.

create or replace function public._lab_firm(p_firm uuid) returns boolean
language sql stable security definer set search_path = bots, public as $$
  select exists (
    select 1 from firms f
    where f.id = p_firm and (
      f.slug = any (array['a16z','y-combinator','sequoia','lightspeed','generalcatalyst','plugandplay','accel','greenoaks','khosla-ventures','mio-partners'])
      or f.slug = any (string_to_array(coalesce((select value from ingest_settings where key = 'lab_firm_slugs'), ''), ','))
    )
  );
$$;
revoke all on function public._lab_firm(uuid) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.checked_items(p jsonb)
 RETURNS TABLE(n integer, kind text, section text, field text, item jsonb, url text, f jsonb, outcome text, reason text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare s record; i jsonb; g text; v jsonb; r jsonb; lbl text; t text; notes jsonb;
begin
  n := 0;
  for s in select x.key k, x.value val from jsonb_each(case when jsonb_typeof(p->'sections') = 'object' then p->'sections' else '{}' end) x loop
    for i in select y from jsonb_array_elements(case when jsonb_typeof(s.val) = 'array' then s.val else '[]' end) y loop
      n := n + 1; kind := 'section'; section := _section_key(s.k); field := null; item := i;
      url := case when jsonb_typeof(i) = 'object' then coalesce(i->>'source', i->>'url', i->>'source_url') end;
      r := _check_item(section, 'section', null, i, url);
      f := r->'f'; outcome := r->>'outcome'; reason := r->>'reason';
      if outcome = 'ok' and _data_rule(section, kind, f, url) is not null then outcome := 'rejected'; reason := _data_rule(section, kind, f, url); end if;
      return next;
    end loop;
  end loop;
  notes := p->'notes';
  if jsonb_typeof(notes) = 'string' then notes := jsonb_build_array(notes); end if;
  if jsonb_typeof(notes) = 'array' then
    for i in select y from jsonb_array_elements(notes) y loop
      if jsonb_typeof(i) <> 'string' then continue; end if;
      t := nullif(btrim(i #>> '{}'), '');
      if t is null then continue; end if;
      n := n + 1; kind := 'note'; section := null; field := null;
      item := jsonb_build_object('note', left(t, 4000));
      url := null; f := item; outcome := 'note'; reason := 'note kept internal (never published)';
      return next;
    end loop;
  end if;
  foreach g in array array['add', 'fix', 'lead'] loop
    for i in select y from jsonb_array_elements(case when jsonb_typeof(p->(case g when 'lead' then 'leads' else g end)) = 'array'
                                                 then p->(case g when 'lead' then 'leads' else g end) else '[]' end) y loop
      n := n + 1; kind := g; item := i; field := i->>'field'; section := _enrich_section(field);
      url := coalesce(i->>'source_url', i->>'source', i->>'url');
      v := case when g = 'fix' then coalesce(i->'correct_value', i->'value') else i->'value' end;
      f := null; reason := null;
      if jsonb_typeof(i) is distinct from 'object' then
        outcome := 'rejected'; reason := 'each entry must be an object {field, value, source_url}';
      elsif jsonb_typeof(v) = 'object' then
        r := _check_item(section, g, field, v || jsonb_build_object('source', url), url);
        f := r->'f'; outcome := r->>'outcome'; reason := r->>'reason';
      else
        t := btrim(v #>> '{}');
        if _src_reason(url, section) is not null then
          outcome := 'rejected'; reason := _src_reason(url, section);
        elsif nullif(t, '') is null then
          outcome := 'rejected'; reason := 'empty item';
        elsif g = 'fix' and section = 'people' and field ~ '\[[^\]]+\]' then
          reason := _note_text(t, 200);
          outcome := case when reason is null then 'ok' else 'rejected' end;
          f := jsonb_build_object('person', substring(field from '\[([^\]]+)\]'), 'value', t);
        elsif section in ('overview', 'funds') and lower(field) !~ '^(funds|limitedpartners|limited_partners|lps)' then
          lbl := case when lower(field) ~ '^hq' then 'Headquarters' when lower(field) ~ '^founded' then 'Founded'
                      when lower(field) ~ '^(aum|facts\.aum)' then 'Regulatory AUM' when lower(field) ~ '^legal_entities' then 'Legal entity'
                      when lower(field) ~ '^website' then 'Website' else initcap(replace(split_part(field, '.', 1), '_', ' ')) end;
          reason := coalesce(_note_text(t, 300), case when lower(field) ~ '^(aum|facts\.aum)' and g <> 'lead' and t !~ '\d' then 'AUM needs a numeric figure' end);
          outcome := case when reason is null then 'ok' else 'rejected' end;
          f := jsonb_build_object('label', lbl, 'value', t, 'scalar', true);
        else
          outcome := 'rejected'; reason := 'value must be an object: ' || _section_fields(section) || ' (or mark free text {"note": "..."})';
        end if;
      end if;
      if outcome = 'ok' and _data_rule(section, kind, f, url) is not null then outcome := 'rejected'; reason := _data_rule(section, kind, f, url); end if;
      return next;
    end loop;
  end loop;
end $function$;



create or replace function public.research_enrich(p_bot text, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = bots, public as $$
declare fid uuid; reg text := nullif(p_payload->>'registry_id', ''); slg text := nullif(p_payload->>'slug', ''); page text; eid bigint;
  acc int; rej int; nts int; errs jsonb; v boolean; pub jsonb; onpage boolean := false; enricher boolean := p_bot = 'toxy-enricher';
  lab boolean;
begin
  perform bots.apply_limits();
  if slg is not null then select id into fid from firms where slug = slg and deleted_at is null; end if;
  if fid is null and reg is not null then
    select id into fid from firms where deleted_at is null and not coalesce(is_test, false) and registry_id = _registry_target(reg)
     order by published desc limit 1;
    if fid is null and enricher and exists (select 1 from research_queue where registry_id = reg) then
      fid := ensure_firm_for_registry(reg, false);
    end if;
  end if;
  if fid is null and reg is null then return jsonb_build_object('error', 'unknown firm: send "slug" (page slug) or "registry_id"'); end if;
  if reg is null then reg := _firm_queue_id(fid); end if;
  lab := public._lab_firm(fid);
  select slug into page from firms where id = fid and published;
  select count(*) filter (where outcome = 'ok'), count(*) filter (where outcome = 'rejected'),
    count(*) filter (where outcome = 'note' and (kind is distinct from 'note' or lab)),
    coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'section', section, 'field', field, 'item', left(item::text, 160), 'url', url, 'reason', reason))
      filter (where outcome = 'rejected'), '[]')
    into acc, rej, nts, errs from checked_items(p_payload);
  if (select coalesce(max(id), 0) + 1 from research_enrichments) < _rules_cutoff() then
    select count(*) filter (where ok), count(*) filter (where not ok),
      coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'section', section, 'field', field, 'item', left(txt, 160), 'url', url, 'reason', reason)) filter (where not ok), '[]')
      into acc, rej, errs from enrichment_items(p_payload);
    nts := 0;
  end if;
  v := acc > 0;
  insert into research_enrichments(bot_id, registry_id, slug, firm_id, payload, valid, errors, accepted, rejected)
  values (p_bot, reg, coalesce(slg, (select slug from firms where id = fid)), fid, p_payload, v, errs, acc, rej) returning id into eid;
  if enricher and eid >= _rules_cutoff() then
    insert into publish_checks(origin, origin_id, bot_id, firm_id, section, kind, field, item, outcome, reason)
    select 'enrichment', eid, p_bot, fid, section, kind, field, item, outcome, reason
      from checked_items(p_payload)
     where outcome in ('rejected', 'note')
       and (kind is distinct from 'note' or lab);
  end if;
  onpage := enricher and exists (
    select 1 from publish_checks
     where origin = 'enrichment' and origin_id = eid and outcome in ('published', 'merged'));
  if onpage and fid is not null then
    update firms set indexable = true
     where id = fid and published and deleted_at is null and not coalesce(is_test, false) and data_status = 'real' and not indexable;
    select slug into page from firms where id = fid and published;
  end if;
  if enricher and fid is not null and reg is not null then
    update firm_requests set firm_id = fid, updated_at = now()
     where status = 'linked' and firm_id is null and registry_id in (reg, _registry_target(reg));
    perform _firm_request_enqueue(r.id) from firm_requests r
     where r.firm_id = fid and r.status = 'linked' and r.registry_id in (reg, _registry_target(reg));
  end if;
  select coalesce(jsonb_object_agg(outcome, c), '{}') into pub from (select outcome, count(*) c from publish_checks where origin = 'enrichment' and origin_id = eid group by 1) x;
  return jsonb_build_object('enrichment_id', eid, 'firm', coalesce(page, slg), 'registry_id', reg, 'on_page', onpage, 'valid', v,
    'accepted_items', acc, 'rejected_items', rej, 'notes_kept', nts, 'rejected', errs, 'outcomes', pub,
    'conflicts', coalesce((select jsonb_agg(jsonb_build_object('section', section, 'item', left(item::text, 160), 'reason', reason))
                             from publish_checks where origin = 'enrichment' and origin_id = eid and outcome = 'conflict'), '[]'),
    'rules', 'docs/DATA_RULES.md: one structured item per fact; free text only as {"note": "..."}');
end $$;
revoke all on function public.research_enrich(text, jsonb) from public, anon, authenticated;
grant execute on function public.research_enrich(text, jsonb) to bot_writer;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.research_enrich(text, jsonb) to service_role;
  end if;
end $$;

-- Existing lab-firm payloads: save top-level notes as verdicts. Does not publish. Does not delete.
insert into public.publish_checks(origin, origin_id, bot_id, firm_id, section, kind, field, item, outcome, reason)
select 'enrichment', e.id, e.bot_id, e.firm_id, c.section, c.kind, c.field, c.item, c.outcome, c.reason
from bots.research_enrichments e
cross join lateral public.checked_items(e.payload) c
where public._lab_firm(e.firm_id)
  and c.kind = 'note' and c.outcome = 'note'
  and not exists (
    select 1 from public.publish_checks p
    where p.origin = 'enrichment' and p.origin_id = e.id and p.firm_id = e.firm_id
      and p.outcome = 'note' and p.item = c.item
  );
