-- Rollback for 20261028040000_lab_rules.sql.
-- Drops the trigger. Leaves conflict_weekly rows in place. Nothing is deleted.

drop trigger if exists lab_rule_on_check on public.publish_checks;
drop function if exists public._lab_rule_on_check();
