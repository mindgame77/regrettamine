-- Undo 20261108040000_lightspeed_public_slug: put firm 6 back on lightspeed-venture-partners.
-- Does not delete rows. No-op when the v2 tables are absent or the short slug is not firm 6.
do $mig$
begin
  if to_regclass('public.v2_firms') is null or to_regclass('public.v2_firm_live') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;

  update public.v2_firm_live
     set slug = 'lightspeed-venture-partners'
   where firm_id = 6
     and slug = 'lightspeed';

  update public.v2_firms
     set slug = 'lightspeed-venture-partners'
   where firm_id = 6
     and slug = 'lightspeed'
     and display_name = 'Lightspeed Venture Partners';
end
$mig$;
