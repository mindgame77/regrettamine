-- Rollback for 20261029180000_my_firms_refund_note.sql: my_firms() without refunded_at (prod def of 2026-10-29).
CREATE OR REPLACE FUNCTION public.my_firms()
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with ch as (select ce.firm_id, min(ce.created_at) at from check_events ce join check_balances b on b.id = ce.balance_id
              where b.user_id = auth.uid() and ce.kind like 'spend_%' and ce.firm_id is not null group by ce.firm_id),
       sv as (select firm_id, created_at at from watchlist where profile_id = auth.uid()),
       ids as (select firm_id from ch union select firm_id from sv)
  select coalesce(json_agg(json_build_object('slug', f.slug, 'name', f.name, 'short_name', f.short_name, 'hq', f.hq,
    'checked_at', ch.at, 'saved', sv.at is not null, 'saved_at', sv.at,
    'clear', r.clear, 'review', r.review, 'wk', r.wk) order by greatest(ch.at, sv.at) desc), '[]'::json)
  from ids join firms f on f.id = ids.firm_id
  left join ch on ch.firm_id = f.id left join sv on sv.firm_id = f.id
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
