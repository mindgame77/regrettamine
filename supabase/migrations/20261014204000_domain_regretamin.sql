-- Domain correction (Alex, Oct 14 2026): regretamin.com (no e).
-- Replaces regretamine.com / regrettamine.com in every public text/jsonb column.
-- The GitHub path mindgame77.github.io/regrettamine is not a .com and is untouched.
do $$
declare r record;
begin
  for r in
    select c.table_name, c.column_name, c.data_type
    from information_schema.columns c
    join information_schema.tables t on t.table_schema = c.table_schema and t.table_name = c.table_name
    where c.table_schema = 'public' and t.table_type = 'BASE TABLE'
      and c.data_type in ('text', 'character varying', 'jsonb')
      and c.table_name <> 'app_secrets'
  loop
    if r.data_type = 'jsonb' then
      execute format('update public.%I set %I = regexp_replace(%I::text, %L, %L, %L)::jsonb where %I::text ~* %L',
        r.table_name, r.column_name, r.column_name, '[Rr]egret{1,2}amine\.com', 'regretamin.com', 'g', r.column_name, 'regret{1,2}amine\.com');
    else
      execute format('update public.%I set %I = regexp_replace(%I, %L, %L, %L) where %I ~* %L',
        r.table_name, r.column_name, r.column_name, '[Rr]egret{1,2}amine\.com', 'regretamin.com', 'g', r.column_name, 'regret{1,2}amine\.com');
    end if;
  end loop;
end $$;
