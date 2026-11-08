-- Lightspeed's public page is /vc/lightspeed/, the same short slug a16z and Sequoia use.
-- firm_meta and _v2_live_id match v2_firm_live.slug. The slug written into the page is v2_firms.slug.
-- Firm 6 was activated as lightspeed-venture-partners, so /vc/lightspeed/ 404s and the page data
-- does not load for that path. Facts stay on firm_id 6. No row is deleted.
-- /vc/lightspeed-venture-partners/ then 301s through firm_redirect, which already matches that
-- name to the legacy firms.slug lightspeed, the same way sequoia-capital reaches /vc/sequoia/.
-- The legacy firms row is left as it is (published, launch_page false), same as Sequoia.
-- CI has no v2 schema: this is a no-op there.
-- Undo: supabase/rollbacks/20261108040000_lightspeed_public_slug.sql
do $mig$
begin
  if to_regclass('public.v2_firms') is null or to_regclass('public.v2_firm_live') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;

  if exists (
    select 1 from public.v2_firms
    where slug = 'lightspeed' and firm_id <> 6
  ) then
    raise exception 'lightspeed slug is already used by another v2 firm';
  end if;

  update public.v2_firms
     set slug = 'lightspeed'
   where firm_id = 6
     and slug = 'lightspeed-venture-partners'
     and display_name = 'Lightspeed Venture Partners';

  update public.v2_firm_live
     set slug = 'lightspeed'
   where firm_id = 6
     and slug = 'lightspeed-venture-partners'
     and exists (
       select 1 from public.v2_firms
       where firm_id = 6
         and slug = 'lightspeed'
         and display_name = 'Lightspeed Venture Partners'
     );
end
$mig$;
