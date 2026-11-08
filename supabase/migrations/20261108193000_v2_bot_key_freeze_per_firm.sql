-- A bot key freezes at 100 rejections for one firm in a Pacific day.
-- The other freeze is unchanged: more than 100 distinct firms in an hour.
-- CI has no v2 schema: the function patch is a no-op there.
-- Clears the freeze on bot_key_id 322 (external-muse-bot) after the new rule is in place.
-- Undo: supabase/rollbacks/20261108193000_v2_bot_key_freeze_per_firm.sql
-- The undo puts back the 10-rejections-across-all-firms count. It does not freeze key 322 again.
do $mig$
declare
  d text;
  n text;
  old text;
  new text;
  updated int;
begin
  if to_regprocedure('public.v2_research_submit(uuid,jsonb,boolean)') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;

  select pg_get_functiondef('public.v2_research_submit(uuid,jsonb,boolean)'::regprocedure) into d;
  if position('rejections today for one firm' in d) = 0 then
    old := $old$  SELECT count(*) INTO rej_today FROM public.v2_research_submissions WHERE bot_key_id = bk.bot_key_id AND status LIKE 'Rejected:%'
    AND received_at >= date_trunc('day', now() AT TIME ZONE 'America/Los_Angeles') AT TIME ZONE 'America/Los_Angeles';
  SELECT count(DISTINCT coalesce(firm_id::text, payload->>'firm_ref')) INTO firms_hour FROM public.v2_research_submissions
    WHERE bot_key_id = bk.bot_key_id AND received_at > now() - interval '1 hour';
  frz := CASE WHEN rej_today >= 10 THEN format('%s rejections today', rej_today) WHEN firms_hour > 100 THEN format('%s firms in the last hour', firms_hour) END;$old$;
    new := $new$  SELECT coalesce(max(n), 0)::int INTO rej_today FROM (
    SELECT count(*) AS n FROM public.v2_research_submissions
    WHERE bot_key_id = bk.bot_key_id AND status LIKE 'Rejected:%'
      AND received_at >= date_trunc('day', now() AT TIME ZONE 'America/Los_Angeles') AT TIME ZONE 'America/Los_Angeles'
    GROUP BY coalesce(firm_id::text, payload->>'firm_ref')
  ) one_firm;
  SELECT count(DISTINCT coalesce(firm_id::text, payload->>'firm_ref')) INTO firms_hour FROM public.v2_research_submissions
    WHERE bot_key_id = bk.bot_key_id AND received_at > now() - interval '1 hour';
  frz := CASE WHEN rej_today >= 100 THEN format('%s rejections today for one firm', rej_today) WHEN firms_hour > 100 THEN format('%s firms in the last hour', firms_hour) END;$new$;
    if length(d) - length(replace(d, old, '')) <> length(old) then
      raise exception 'v2_research_submit: freeze rule anchor missing or not unique';
    end if;
    n := replace(d, old, new);
    if n = d
       or position('rejections today for one firm' in n) = 0
       or position('rej_today >= 100 THEN' in n) = 0
       or position('rej_today >= 10 THEN' in n) > 0
       or position('firms_hour > 100' in n) = 0
       or position('format(''%s firms in the last hour'', firms_hour)' in n) = 0 then
      raise exception 'v2_research_submit: freeze rule patch did not apply';
    end if;
    execute n;
  end if;

  if to_regclass('public.v2_bot_keys') is null then
    raise exception 'v2_bot_keys missing; key 322 was not unfrozen';
  end if;
  UPDATE public.v2_bot_keys SET frozen=false, freeze_date=NULL, freeze_reason=NULL WHERE bot_key_id=322;
  get diagnostics updated = row_count;
  if updated <> 1 then
    raise exception 'expected to unfreeze bot_key_id 322, updated %', updated;
  end if;
end
$mig$;
