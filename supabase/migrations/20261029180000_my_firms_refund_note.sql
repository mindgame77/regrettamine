-- My firms refund note (approved mockup 06-myfirms-refund-note): my_firms() returns refunded_at when the user's check on a
-- firm was not finished in 24 hours and its credit was refunded automatically (ondemand_refund_expired via ondemand_tick).
-- Read only; no data written. Rollback: supabase/rollbacks/20261029180000_my_firms_refund_note.sql
CREATE OR REPLACE FUNCTION public.my_firms()
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with ch as (select ce.firm_id, min(ce.created_at) at from check_events ce join check_balances b on b.id = ce.balance_id
              where b.user_id = auth.uid() and ce.kind like 'spend_%' and ce.firm_id is not null group by ce.firm_id),
       -- 24 h auto-refund (ondemand_refund_expired): research_requests.status = 'refunded' with refunded_at, and a matching
       -- check_events 'refund_ondemand'. Shown only while the firm is not open again (spends minus refunds <= 0).
       rf as (select rq.firm_id, max(rq.refunded_at) at from research_requests rq join check_balances b on b.id = rq.balance_id
              where b.user_id = auth.uid() and rq.status = 'refunded' and rq.refunded_at is not null
                and rq.spend_kind in ('spend_free', 'spend_paid') group by rq.firm_id
              having (select coalesce(sum(case when ce.kind like 'spend_%' then 1 when ce.kind = 'refund_ondemand' then -1 else 0 end), 0)
                        from check_events ce join check_balances b2 on b2.id = ce.balance_id
                       where b2.user_id = auth.uid() and ce.firm_id = rq.firm_id) <= 0),
       sv as (select firm_id, created_at at from watchlist where profile_id = auth.uid()),
       ids as (select firm_id from ch union select firm_id from sv)
  select coalesce(json_agg(json_build_object('slug', f.slug, 'name', f.name, 'short_name', f.short_name, 'hq', f.hq,
    'checked_at', ch.at, 'saved', sv.at is not null, 'saved_at', sv.at,
    'refunded_at', rf.at, 'clear', r.clear, 'review', r.review, 'wk', r.wk) order by greatest(ch.at, sv.at) desc), '[]'::json)
  from ids join firms f on f.id = ids.firm_id
  left join ch on ch.firm_id = f.id left join rf on rf.firm_id = f.id left join sv on sv.firm_id = f.id
  cross join lateral (
    select count(*) filter (where st in ('clear', 'nf')) clear,
           count(*) filter (where st in ('review', 'red')) review,
           count(*) filter (where st = 'wk') wk
    from (
      select e->>'state' st from json_array_elements(public._firm_checks(f.id)) e
      where public._lab_firm(f.id)
      union all
      select state from firm_check_rows where firm_id = f.id and not public._lab_firm(f.id)
    ) s
  ) r
  where auth.uid() is not null
$function$;
