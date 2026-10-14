-- Approved copy changes (Alex, Oct 14 2026). NOT APPLIED YET.
-- 1. Brand shown to users is Regretamin (no e). The domain regretamine.com and the
--    GitHub Pages path /regrettamine/ are unchanged (lowercase domain never matches).
-- 2. a16z verdict: "Safe to take a meeting" -> "Reasonable to take a meeting".
-- Mirrors data/funds/*.json so a Supabase build matches the JSON build.

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
      and c.table_name not in ('app_secrets', 'ui_strings')
  loop
    execute format(
      'update public.%I set %I = replace(regexp_replace(%I, %L, %L, %L), %L, %L) where %I ~ %L or %I like %L',
      rec.table_name, rec.column_name, rec.column_name,
      'Regretamine(?!\.com)', 'Regretamin', 'g',
      'Safe to take a meeting', 'Reasonable to take a meeting',
      rec.column_name, 'Regretamine(?!\.com)',
      rec.column_name, '%Safe to take a meeting%'
    );
  end loop;
end $$;

update public.report_bundles
set payload = jsonb_set(
  payload,
  '{html}',
  to_jsonb(replace(regexp_replace(payload->>'html', 'Regretamine(?!\.com)', 'Regretamin', 'g'),
                   'Safe to take a meeting', 'Reasonable to take a meeting'))
)
where payload->>'html' ~ 'Regretamine(?!\.com)'
   or payload->>'html' like '%Safe to take a meeting%';
