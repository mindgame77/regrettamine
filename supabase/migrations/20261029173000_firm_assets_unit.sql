-- AUM tile unit (2026-10-29): _firm_assets kept only the digits ('$18.27B per Item 5F' -> '$18.27'), so the tile lost its unit.
-- It now keeps a unit written right after the number: B/M/K/T or billion/million/thousand/trillion/bn/mn/mm.
-- The page (aumFigure) turns the words into the letter. Same rows, same order; only the returned text gains the unit.
-- Preview on prod: 16 of 156 matching facts gain a unit, all correct (lab firms: greenoaks only).
-- Rollback: supabase/rollbacks/20261029173000_firm_assets_unit.sql
create or replace function public._firm_assets(p_firm uuid)
 returns text
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select coalesce(
    (select (regexp_match(f.value, '\$[0-9][0-9,]*(?:\.[0-9]+)?(?:[[:space:]]*(?:trillion|billion|bn|million|mn|mm|thousand|[TBMK])(?![[:alnum:]]))?', 'i'))[1]
       from firm_profile_facts f
      where f.firm_id = p_firm and not f.hidden
        and f.value ~* '(item[[:space:]]*5[[:space:]]*f|regulatory[[:space:]]+aum|regulatory[[:space:]]+assets)'
        and f.value !~* 'schedule[[:space:]]*d|gross[[:space:]]+asset'
        and f.value ~ '\$[0-9]'
      order by case when f.value ~* 'item[[:space:]]*5[[:space:]]*f' then 0 else 1 end, f.sort_order
      limit 1),
    (select fi.aum_display from firms fi where fi.id = p_firm and fi.aum_display ~ '^\$')
  );
$function$;
