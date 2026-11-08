-- The per-firm rejection count first used the name n. This function already uses n.
-- A submit then failed. This renames that count to firm_rej. The 100-per-firm rule
-- and the more-than-100-firms-in-an-hour rule stay. No rows are changed.
-- CI has no v2 schema: this is a no-op there.
-- Undo is the same rollback as the per-firm rule: supabase/rollbacks/20261108193000_v2_bot_key_freeze_per_firm.sql
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
  if position('AS firm_rej' in d) > 0 then
    raise notice 'v2_research_submit per-firm count already uses firm_rej';
    return;
  end if;
  old := $old$  SELECT coalesce(max(n), 0)::int INTO rej_today FROM (
    SELECT count(*) AS n FROM public.v2_research_submissions
    WHERE bot_key_id = bk.bot_key_id AND status LIKE 'Rejected:%'
      AND received_at >= date_trunc('day', now() AT TIME ZONE 'America/Los_Angeles') AT TIME ZONE 'America/Los_Angeles'
    GROUP BY coalesce(firm_id::text, payload->>'firm_ref')
  ) one_firm;$old$;
  new := $new$  SELECT coalesce(max(firm_rej), 0)::int INTO rej_today FROM (
    SELECT count(*) AS firm_rej FROM public.v2_research_submissions
    WHERE bot_key_id = bk.bot_key_id AND status LIKE 'Rejected:%'
      AND received_at >= date_trunc('day', now() AT TIME ZONE 'America/Los_Angeles') AT TIME ZONE 'America/Los_Angeles'
    GROUP BY coalesce(firm_id::text, payload->>'firm_ref')
  ) one_firm;$new$;
  if length(d) - length(replace(d, old, '')) <> length(old) then
    raise exception 'v2_research_submit: per-firm count anchor missing or not unique';
  end if;
  n := replace(d, old, new);
  if position('max(firm_rej)' in n) = 0 or position('max(n)' in n) > 0 or position('firms_hour > 100' in n) = 0 then
    raise exception 'v2_research_submit: per-firm count rename did not apply';
  end if;
  execute n;
end
$mig$;
