-- Old website RPCs. The functions stay. anon, authenticated, and the PUBLIC
-- default cannot call them. service_role keeps execute.
-- Unchanged: my_billing, access_tier, set_fund_alert_kind, set_watch_alert_kind,
-- watch_fund, unwatch_fund, is_admin.
-- Undo with supabase/rollbacks/20261027204000_revoke_old_site_rpcs.sql.
-- That file is not applied by scripts/migrate.py.

revoke execute on function
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
  public.open_report(text, text)
from public, anon, authenticated;

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
  public.set_fund_alert(text, boolean),
  public.open_report(text, text)
to service_role;
