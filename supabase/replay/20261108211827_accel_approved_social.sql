-- Not a migration. scripts/migrate.py does not run this file.
-- Run only after 20261108211827_v2_publish_social_accounts.sql is applied and the owner says yes.
-- Publishes Accel (firm 8) queue 6573, 6574, 6575 only. Rows 49, 50, 51. Submissions 8286, 8287, 8288.
-- Read 2026-11-08. Source https://www.accel.com/. A plain run ends in rollback, so nothing is saved.
-- To keep the three publishes, change the final rollback to commit after the checks pass.

begin;

do $replay$
declare
  msg text;
begin
  if to_regprocedure('public.v2_publish_queue_item(bigint)') is null
     or position('F11.8 social' in pg_get_functiondef('public.v2_publish_queue_item(bigint)'::regprocedure)) > 0 then
    raise exception 'replay: apply the social publish migration first';
  end if;

  if (select count(*) from v2_social_accounts where firm_id = 8) <> 3 then
    raise exception 'replay: firm 8 does not have exactly three social rows';
  end if;

  if not exists (
    select 1 from v2_checker_queue q
    join v2_social_accounts s on s.row_id = q.row_id and s.submission_id = q.submission_id
    where q.queue_id = 6573 and q.submission_id = 8286 and q.firm_id = 8 and q.row_id = 49
      and q.table_name = 'v2_social_accounts' and q.status = 'passed' and not q.archived
      and s.platform = 'X' and s.account_url = 'https://x.com/accel' and s.follower_count = 340417
      and s.source_url = 'https://www.accel.com/' and s.source_level = 2
      and not s.is_current and not s.archived and not s.nothing_found
  ) or not exists (
    select 1 from v2_checker_queue q
    join v2_social_accounts s on s.row_id = q.row_id and s.submission_id = q.submission_id
    where q.queue_id = 6574 and q.submission_id = 8287 and q.firm_id = 8 and q.row_id = 50
      and q.table_name = 'v2_social_accounts' and q.status = 'passed' and not q.archived
      and s.platform = 'LinkedIn' and s.account_url = 'https://www.linkedin.com/company/accel-vc/' and s.follower_count = 347258
      and s.source_url = 'https://www.accel.com/' and s.source_level = 2
      and not s.is_current and not s.archived and not s.nothing_found
  ) or not exists (
    select 1 from v2_checker_queue q
    join v2_social_accounts s on s.row_id = q.row_id and s.submission_id = q.submission_id
    where q.queue_id = 6575 and q.submission_id = 8288 and q.firm_id = 8 and q.row_id = 51
      and q.table_name = 'v2_social_accounts' and q.status = 'passed' and not q.archived
      and s.platform = 'YouTube' and s.account_url = 'https://www.youtube.com/@AccelVC' and s.follower_count = 27000
      and s.source_url = 'https://www.accel.com/' and s.source_level = 2
      and not s.is_current and not s.archived and not s.nothing_found
  ) then
    raise exception 'replay: Accel approved social rows do not match the 2026-11-08 read';
  end if;

  select public.v2_publish_queue_item(6573) into msg;
  if msg <> 'Confirmed: published' then raise exception 'replay: queue 6573 returned %', msg; end if;
  select public.v2_publish_queue_item(6574) into msg;
  if msg <> 'Confirmed: published' then raise exception 'replay: queue 6574 returned %', msg; end if;
  select public.v2_publish_queue_item(6575) into msg;
  if msg <> 'Confirmed: published' then raise exception 'replay: queue 6575 returned %', msg; end if;

  if (select count(*) from v2_social_accounts
       where firm_id = 8 and row_id in (49, 50, 51) and is_current and not archived) <> 3 then
    raise exception 'replay: Accel social rows were not all published';
  end if;
end
$replay$;

-- Safe default. Nothing is saved until this line is changed to commit.
rollback;
