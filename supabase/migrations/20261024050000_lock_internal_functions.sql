-- Lock down internal SECURITY DEFINER functions (2026-10-23).
-- Webhook, billing, build and trigger functions: only service_role (and owner) may call them.
-- Trigger functions run from their triggers without caller EXECUTE; firm_page/watch_fund/etc. call
-- unlock_firm, sync_watch_alerts and stripe_note_card as the definer, so those keep working.
do $$
declare f text;
begin
  foreach f in array array[
    'public.apply_stripe_event(jsonb)',
    'public.apply_subscription(uuid,text,text,timestamp with time zone)',
    'public.stripe_note_card(jsonb)',
    'public.store_report_page(text,text)',
    'public.sync_watch_alerts(uuid)',
    'public.unlock_firm(text,uuid,boolean)',
    'public.checks_from_upload_trg()',
    'public.handle_new_user()',
    'public.record_fact_event()',
    'public.record_published_review()',
    'public.sync_watch_alerts_from_view()'
  ] loop
    if to_regprocedure(f) is not null then
      execute format('revoke execute on function %s from public', f);
      if exists (select 1 from pg_roles where rolname = 'anon') then
        execute format('revoke execute on function %s from anon', f);
      end if;
      if exists (select 1 from pg_roles where rolname = 'authenticated') then
        execute format('revoke execute on function %s from authenticated', f);
      end if;
      if exists (select 1 from pg_roles where rolname = 'service_role') then
        execute format('grant execute on function %s to service_role', f);
      end if;
    end if;
  end loop;

  -- Signed-in user actions: they check auth.uid() inside; anon has no business calling them.
  foreach f in array array[
    'public.watch_fund(text)',
    'public.unwatch_fund(text)',
    'public.set_fund_alert(text,boolean)',
    'public.set_fund_alert_kind(text,text,boolean)',
    'public.set_watch_alert_kind(text,boolean)',
    'public.delete_my_account()'
  ] loop
    if to_regprocedure(f) is not null and exists (select 1 from pg_roles where rolname = 'anon') then
      execute format('revoke execute on function %s from public', f);
      execute format('revoke execute on function %s from anon', f);
      if exists (select 1 from pg_roles where rolname = 'authenticated') then
        execute format('grant execute on function %s to authenticated', f);
      end if;
    end if;
  end loop;
end $$;
