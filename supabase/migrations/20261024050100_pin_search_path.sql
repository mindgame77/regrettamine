-- Pin search_path on the helper functions flagged by the Supabase advisor (function_search_path_mutable).
-- They only use public objects and pg_catalog built-ins.
do $$
declare f text;
begin
  foreach f in array array[
    'public._ck_finding(jsonb)',
    'public._ck_n(text)',
    'public._ck_named(jsonb)',
    'public._ck_non_us(jsonb)',
    'public._ck_ts(text)',
    'public.firm_list_row(firms)',
    'public.protect_bundle_html()',
    'public.protect_report_html()',
    'public.report_html_ok(text)',
    'public.stripe_card_label(text,text)',
    'public.stripe_money(integer)',
    'public.stripe_plan_name(text)',
    'public.stripe_price_cents(text)',
    'public.stripe_unix(text)',
    'public.tier_list_limit(text)',
    'public.ui_strings_touch()',
    'public.vc_ai_check_approve()',
    'public.vc_fact_mark_stale()'
  ] loop
    if to_regprocedure(f) is not null then
      execute format('alter function %s set search_path = public, pg_temp', f);
    end if;
  end loop;
end $$;
