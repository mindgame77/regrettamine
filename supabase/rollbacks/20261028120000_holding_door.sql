-- Removes the holding door. The Checker goes back to checking each new lab row as it arrives.
-- Does not delete submissions. Does not turn a blocked key back on. Alex still uses door_unblock
-- before this file is run if a bot should work again.

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'checker-door-drain') then
      perform cron.unschedule('checker-door-drain');
    end if;
  end if;
end $$;

create or replace function public.checker_on_submission() returns trigger
language plpgsql security definer set search_path = bots, public as $$
begin
  if not public._checker_publish_on() then return null; end if;
  begin
    perform public.checker_publish_submission(new.id);
  exception when others then
    insert into checker_holding(firm_id, origin, origin_id, kind, outcome, reason, item)
    values (null, 'submission', new.id, 'row', 'failure', sqlerrm, new.payload);
  end;
  return null;
end $$;

drop function if exists public.door_unblock(text);
drop function if exists public.checker_drain(int);
drop function if exists public._door_fail_rate(text);
drop function if exists public._door_admit(text, text, jsonb);
drop function if exists public._door_alert(text, text, text);
drop function if exists public._door_known(text);
drop function if exists public._door_key(text, jsonb);
