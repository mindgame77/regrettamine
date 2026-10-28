-- Drop the retired website functions. Nothing in the launch site, the edge
-- functions, cron, or another function, view, or trigger calls them.
-- The functions are saved in supabase/rollbacks/20261028060000_drop_old_site_rpcs.sql.
-- Kept: my_billing, access_tier, set_fund_alert_kind, set_watch_alert_kind,
-- watch_fund, unwatch_fund, is_admin.

drop function if exists
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
  public.set_fund_alert(text, boolean),
  public.open_report(text, text);
