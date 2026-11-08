-- Limited partners and News are off (Alex, 2026-11-08).
-- The door rejects those two tables. The page does not read them.
-- Rows stay. Nothing is deleted and no table is dropped.
-- The v2 schema is not created by repo migrations; CI skips this.
do $mig$
declare
  d text;
  n text;
  press_at int;
  e1_at int;
begin
  if to_regprocedure('public.v2_research_submit(uuid,jsonb,boolean)') is null
     and to_regprocedure('public.v2_firm_page(text)') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;
  if to_regclass('public.v2_news_items') is null or to_regclass('public.v2_lp_commitments') is null then
    raise exception 'LP or news table is missing; refusing to continue';
  end if;

  if to_regprocedure('public.v2_research_submit(uuid,jsonb,boolean)') is not null then
    select pg_get_functiondef('public.v2_research_submit(uuid,jsonb,boolean)'::regprocedure) into d;
    if position($a$'v2_lp_commitments'$a$ in d) = 0 and position($a$'v2_news_items'$a$ in d) = 0 then
      raise notice 'v2_research_submit already omits LP and news';
    else
      if position($a$'v2_lp_commitments',$a$ in d) = 0 or position($a$'v2_news_items',$a$ in d) = 0 then
        raise exception 'v2_research_submit: table list anchor missing';
      end if;
      n := replace(replace(d, $a$'v2_lp_commitments',$a$, ''), $a$'v2_news_items',$a$, '');
      if position($a$'v2_lp_commitments'$a$ in n) > 0 or position($a$'v2_news_items'$a$ in n) > 0
         or n = d then
        raise exception 'v2_research_submit: LP and news were not removed from src_tables';
      end if;
      execute n;
    end if;
  end if;

  if to_regprocedure('public.v2_firm_page(text)') is not null then
    select pg_get_functiondef('public.v2_firm_page(text)'::regprocedure) into d;
    press_at := position('-- press' in d);
    e1_at := position('-- E1: Team' in d);
    if press_at = 0 and position('key'',''press''' in d) = 0 and position('key'',''lps''' in d) = 0 then
      raise notice 'v2_firm_page already skips press and LPs';
    else
      if press_at = 0 or e1_at = 0 or e1_at < press_at then
        raise exception 'v2_firm_page: press block anchor missing';
      end if;
      n := substring(d from 1 for press_at - 1)
        || '-- Limited partners and News are off (Alex, 2026-11-08). Rows stay stored. These blocks are not read.'
        || E'\n  '
        || substring(d from e1_at);
      if position('v2_news_items' in n) > 0 or position('v2_lp_commitments' in n) > 0
         or position('key'',''press''' in n) > 0 or position('key'',''lps''' in n) > 0 then
        raise exception 'v2_firm_page: press and LP blocks were not skipped';
      end if;
      execute n;
    end if;
  end if;
end
$mig$;
