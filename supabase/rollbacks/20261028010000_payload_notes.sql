-- Rollback for 20261028010000_payload_notes.sql.
-- Restores checked_items to the body in 20261026050000_data_rules_checker.sql.
-- Does not delete publish_checks rows. Not applied by scripts/migrate.py.

create or replace function public.checked_items(p jsonb)
returns table(n int, kind text, section text, field text, item jsonb, url text, f jsonb, outcome text, reason text)
language plpgsql stable set search_path = public as $$
declare s record; i jsonb; g text; v jsonb; r jsonb; lbl text; t text;
begin
  n := 0;
  for s in select x.key k, x.value val from jsonb_each(case when jsonb_typeof(p->'sections') = 'object' then p->'sections' else '{}' end) x loop
    for i in select y from jsonb_array_elements(case when jsonb_typeof(s.val) = 'array' then s.val else '[]' end) y loop
      n := n + 1; kind := 'section'; section := _section_key(s.k); field := null; item := i;
      url := case when jsonb_typeof(i) = 'object' then coalesce(i->>'source', i->>'url', i->>'source_url') end;
      r := _check_item(section, 'section', null, i, url);
      f := r->'f'; outcome := r->>'outcome'; reason := r->>'reason';
      return next;
    end loop;
  end loop;
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
      return next;
    end loop;
  end loop;
end $$;
