-- Every firm in v2_firms is live as soon as it is added.
-- firm_meta, firm_page, and firm_sitemap read v2_firm_live. This inserts that row
-- on insert into v2_firms, and fills in firms that do not have one yet.
-- An existing live row keeps its slug, note, and live_since. A blank slug is skipped.
-- public.firms is not read or written. Nothing is deleted.
-- CI has no v2 schema: this is a no-op there.
-- Undo: supabase/rollbacks/20261108180000_v2_firms_live_on_insert.sql
-- The undo drops the trigger and function only. Live rows stay.
do $mig$
begin
  if to_regclass('public.v2_firms') is null or to_regclass('public.v2_firm_live') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;

  execute $fn$
create or replace function public.v2_firm_live_on_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $body$
begin
  if nullif(btrim(new.slug::text), '') is null then
    return new;
  end if;
  insert into public.v2_firm_live (firm_id, slug)
  values (new.firm_id, lower(btrim(new.slug::text)))
  on conflict (firm_id) do nothing;
  return new;
end
$body$
$fn$;

  execute 'revoke all on function public.v2_firm_live_on_insert() from public, anon, authenticated';
  execute 'grant execute on function public.v2_firm_live_on_insert() to service_role';

  execute 'drop trigger if exists v2_firms_live_on_insert on public.v2_firms';
  execute $trg$
create trigger v2_firms_live_on_insert
after insert on public.v2_firms
for each row execute function public.v2_firm_live_on_insert()
$trg$;

  execute $back$
insert into public.v2_firm_live (firm_id, slug)
select f.firm_id, lower(btrim(f.slug::text))
from public.v2_firms f
where nullif(btrim(f.slug::text), '') is not null
  and not exists (
    select 1 from public.v2_firm_live l where l.firm_id = f.firm_id
  )
$back$;
end
$mig$;
