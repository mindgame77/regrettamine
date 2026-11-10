-- Undo v2 research-bot results lookup. Drops the read-only functions only.
-- No table or data is changed.
do $undo$
begin
  drop function if exists public.v2_research_my_results(uuid, int, int, bigint);
  drop function if exists public._v2_research_my_result_items(bigint, int, bigint);
  drop function if exists public._v2_research_not_sent(bigint);
end
$undo$;
