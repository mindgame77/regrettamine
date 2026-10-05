-- Public copy uses Regretamine. The GitHub Pages path /regrettamine/ is unchanged.

do $$
declare
  rec record;
begin
  for rec in
    select c.table_name, c.column_name
    from information_schema.columns c
    join information_schema.tables t
      on t.table_schema = c.table_schema and t.table_name = c.table_name
    where c.table_schema = 'public'
      and t.table_type = 'BASE TABLE'
      and c.data_type in ('text', 'character varying')
      and c.table_name <> 'app_secrets'
  loop
    execute format(
      'update public.%I set %I = replace(replace(%I, %L, %L), %L, %L) where %I like %L or %I like %L',
      rec.table_name, rec.column_name, rec.column_name,
      'regrettamine.com', 'regretamine.com',
      'Regrettamine', 'Regretamine',
      rec.column_name, '%regrettamine.com%',
      rec.column_name, '%Regrettamine%'
    );
  end loop;
end $$;

update public.report_bundles
set payload = jsonb_set(
  payload,
  '{html}',
  to_jsonb(replace(replace(payload->>'html', 'regrettamine.com', 'regretamine.com'), 'Regrettamine', 'Regretamine'))
)
where payload->>'html' like '%Regrettamine%'
   or payload->>'html' like '%regrettamine.com%';
