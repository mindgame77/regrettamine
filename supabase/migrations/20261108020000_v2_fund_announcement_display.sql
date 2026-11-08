-- Latest fund announcement total keeps a leading '~'.
-- One row on the latest date uses that row's display string.
-- Several rows on that same date and url use the numeric sum, prefixed with '~' when any of those displays starts with '~'.
-- Rows from other dates are not added. The v2 schema is not created by repo migrations; CI skips this.
do $mig$
declare
  d text;
  n text;
  old text;
  new text;
begin
  if to_regclass('public.firm_fund_announcements') is null
     or to_regprocedure('public.v2_firm_page(text)') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;

  select pg_get_functiondef('public.v2_firm_page(text)'::regprocedure) into d;
  if position('when count(*)=1 then max(a.display)' in d) > 0 then
    raise notice 'v2_firm_page fund display already patched';
    return;
  end if;

  old := $old$'total_display',public._money_display(sum(a.amount_usd),'USD'),$old$;
  new := $new$'total_display',case when count(*)=1 then max(a.display) when bool_or(left(btrim(a.display),1)='~') then '~'||public._money_display(sum(a.amount_usd),'USD') else public._money_display(sum(a.amount_usd),'USD') end,$new$;
  if position(old in d) = 0 then
    raise exception 'v2_firm_page: fund total_display anchor missing';
  end if;
  n := replace(d, old, new);
  if n = d or position('when count(*)=1 then max(a.display)' in n) = 0 then
    raise exception 'v2_firm_page: fund display patch did not apply';
  end if;
  execute n;
end
$mig$;
