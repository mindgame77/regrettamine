-- Fix: plpgsql variable "n" clashed with firm_check_rows.n ("column reference n is ambiguous"),
-- so every submissions (portal bot) firm was held with an error in dry runs.
create or replace function public._promote_submissions(p_firm uuid) returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare b text := 'publish:' || coalesce(nullif(current_setting('app.publish_batch', true), ''), 'none');
  before jsonb; v_facts int; c int := 0; sid bigint;
begin
  insert into cleanup_backup(batch, firm_id, table_name, row_id, row_data)
  select b, p_firm, 'firm_check_rows', null, to_jsonb(r) from firm_check_rows r where r.firm_id = p_firm;
  select coalesce(jsonb_object_agg(r.n::text, r.state), '{}') into before from firm_check_rows r where r.firm_id = p_firm;
  v_facts := promote_bot_facts(p_firm);
  sid := apply_checks_for_firm(p_firm);
  select count(*) into c from firm_check_rows r where r.firm_id = p_firm and r.state is distinct from (before->>(r.n::text));
  return jsonb_build_object('facts', v_facts, 'check_rows_changed', c, 'submission_id', sid);
end $fn$;
revoke execute on function public._promote_submissions(uuid) from public, anon, authenticated;
