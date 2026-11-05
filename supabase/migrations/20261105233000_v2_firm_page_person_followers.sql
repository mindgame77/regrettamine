-- Team cards: v2_firm_page person items include X and LinkedIn follower counts from v2_people.
-- The v2 schema is not created by repo migrations; on a database without v2_firm_page (CI) this is a no-op.
do $m$
declare
  d text;
  n text;
  old_urls text := $old$'linkedin_url',nullif(btrim(pe.linkedin_url),''),'x_url',nullif(btrim(pe.x_url),'')$old$;
  new_urls text := $new$'linkedin_url',nullif(btrim(pe.linkedin_url),''),'x_url',nullif(btrim(pe.x_url),''),'linkedin_followers',pe.linkedin_followers,'x_followers',pe.x_followers$new$;
begin
  if to_regprocedure('public.v2_firm_page(text)') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'v2_people' and column_name = 'x_followers'
  ) or not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'v2_people' and column_name = 'linkedin_followers'
  ) then
    raise exception 'v2_people follower columns missing';
  end if;
  select pg_get_functiondef('public.v2_firm_page(text)'::regprocedure) into d;
  if position('''x_followers'',pe.x_followers' in d) > 0 then
    raise notice 'v2_firm_page person followers already patched';
    return;
  end if;
  if position(old_urls in d) = 0 then
    raise exception 'v2_firm_page: person url anchor not found';
  end if;
  n := replace(d, old_urls, new_urls);
  if position('''x_followers'',pe.x_followers' in n) = 0 then
    raise exception 'v2_firm_page: person followers patch did not apply';
  end if;
  execute n;
end
$m$;
