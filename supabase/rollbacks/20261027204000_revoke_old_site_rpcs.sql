-- Not applied by scripts/migrate.py. Run this by hand to give the old site RPCs
-- back to anon and authenticated. set_fund_alert was not granted to anon before
-- the revoke, so it is restored for authenticated only. PUBLIC stays revoked.

grant execute on function
  public.carry_anon_views(text),
  public.fact_record_count(),
  public.firm_id_for_slug(text),
  public.landing_funds(),
  public.my_alert_funds(),
  public.my_report_slugs(),
  public.my_watch_alerts(),
  public.my_watch_slugs(),
  public.public_firm_id(text),
  public.search_funds(text),
  public.open_report(text, text)
to anon, authenticated;

grant execute on function public.set_fund_alert(text, boolean) to authenticated;
