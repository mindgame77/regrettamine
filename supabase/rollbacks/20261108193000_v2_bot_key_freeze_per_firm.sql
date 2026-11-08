-- Puts the rejection freeze back to 10 rejections in a Pacific day across all firms.
-- The more-than-100-firms-in-an-hour freeze stays as it is.
-- Does not freeze bot_key_id 322 again. Nothing is deleted.
do $mig$
declare
  d text;
  n text;
  old text;
  new text;
begin
  if to_regprocedure('public.v2_research_submit(uuid,jsonb,boolean)') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;
  select pg_get_functiondef('public.v2_research_submit(uuid,jsonb,boolean)'::regprocedure) into d;
  if position('rejections today for one firm' in d) = 0 then
    raise notice 'v2_research_submit freeze rule already counts every firm';
    return;
  end if;
  old := $old$  SELECT coalesce(max(firm_rej), 0)::int INTO rej_today FROM (
    SELECT count(*) AS firm_rej FROM public.v2_research_submissions
    WHERE bot_key_id = bk.bot_key_id AND status LIKE 'Rejected:%'
      AND received_at >= date_trunc('day', now() AT TIME ZONE 'America/Los_Angeles') AT TIME ZONE 'America/Los_Angeles'
    GROUP BY coalesce(firm_id::text, payload->>'firm_ref')
  ) one_firm;
  SELECT count(DISTINCT coalesce(firm_id::text, payload->>'firm_ref')) INTO firms_hour FROM public.v2_research_submissions
    WHERE bot_key_id = bk.bot_key_id AND received_at > now() - interval '1 hour';
  frz := CASE WHEN rej_today >= 100 THEN format('%s rejections today for one firm', rej_today) WHEN firms_hour > 100 THEN format('%s firms in the last hour', firms_hour) END;$old$;
  new := $new$  SELECT count(*) INTO rej_today FROM public.v2_research_submissions WHERE bot_key_id = bk.bot_key_id AND status LIKE 'Rejected:%'
    AND received_at >= date_trunc('day', now() AT TIME ZONE 'America/Los_Angeles') AT TIME ZONE 'America/Los_Angeles';
  SELECT count(DISTINCT coalesce(firm_id::text, payload->>'firm_ref')) INTO firms_hour FROM public.v2_research_submissions
    WHERE bot_key_id = bk.bot_key_id AND received_at > now() - interval '1 hour';
  frz := CASE WHEN rej_today >= 10 THEN format('%s rejections today', rej_today) WHEN firms_hour > 100 THEN format('%s firms in the last hour', firms_hour) END;$new$;
  if length(d) - length(replace(d, old, '')) <> length(old) then
    raise exception 'v2_research_submit: per-firm freeze anchor missing or not unique';
  end if;
  n := replace(d, old, new);
  if position('rej_today >= 10 THEN' in n) = 0 or position('rejections today for one firm' in n) > 0 then
    raise exception 'v2_research_submit: freeze rollback did not apply';
  end if;
  execute n;
end
$mig$;
