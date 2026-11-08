-- Undo 20261109000100_v2_check_size_bounds.
-- firm.check_size again returns amount_text. The door again only copies source_date into read_on.
-- Rows in v2_firm_check_sizes stay. Nothing is deleted.
do $mig$
declare
  d text;
  n text;
  old text;
  new text;
begin
  if to_regprocedure('public.v2_firm_page(text)') is not null then
    select pg_get_functiondef('public.v2_firm_page(text)'::regprocedure) into d;
    old := $old$'check_size',(select case when c.min_usd is not null and c.max_usd is not null and c.min_usd = c.max_usd and c.min_usd > 0 and c.min_usd = trunc(c.min_usd) then public._money_display(c.min_usd,'USD') when c.min_usd is not null and c.max_usd is not null and c.min_usd < c.max_usd and c.min_usd > 0 and c.min_usd = trunc(c.min_usd) and c.max_usd = trunc(c.max_usd) then public._money_display(c.min_usd,'USD') || '–' || public._money_display(c.max_usd,'USD') when c.min_usd is null and c.max_usd is not null and c.max_usd > 0 and c.max_usd = trunc(c.max_usd) then 'Up to ' || public._money_display(c.max_usd,'USD') when c.max_usd is null and c.min_usd is not null and c.min_usd > 0 and c.min_usd = trunc(c.min_usd) then public._money_display(c.min_usd,'USD') || '+' else null end from v2_firm_check_sizes c where c.firm_id=fid and c.is_current and not c.archived order by c.read_on desc nulls last, c.id desc limit 1),$old$;
    new := $new$'check_size',(select nullif(btrim(c.amount_text),'') from v2_firm_check_sizes c where c.firm_id=fid and c.is_current and not c.archived and nullif(btrim(c.amount_text),'') is not null order by c.read_on desc nulls last, c.id desc limit 1),$new$;
    if position(old in d) = 0 then
      raise notice 'v2_firm_page check size bounds already absent';
    else
      n := replace(d, old, new);
      if n = d or position('nullif(btrim(c.amount_text)' in n) = 0 then
        raise exception 'v2_firm_page: check size bounds undo did not apply';
      end if;
      execute n;
    end if;
  end if;

  if to_regprocedure('public.v2_research_submit(uuid,jsonb,boolean)') is null then
    raise notice 'v2_research_submit missing, skipped';
    return;
  end if;
  select pg_get_functiondef('public.v2_research_submit(uuid,jsonb,boolean)'::regprocedure) into d;
  old := $old$    IF reason IS NULL AND tbl = 'v2_firm_check_sizes' THEN
      IF fact ? 'currency' AND upper(btrim(coalesce(fact->>'currency',''))) <> 'USD' THEN
        reason := 'check size currency must be USD';
      ELSIF fact ? 'currency' THEN
        fact := fact - 'currency';
      END IF;
      IF reason IS NULL AND NOT (fact ? 'read_on') AND coalesce(fact->>'source_date','') <> '' THEN
        fact := fact || jsonb_build_object('read_on', fact->>'source_date');
      END IF;
      IF reason IS NULL AND nullif(btrim(coalesce(fact->>'amount_text','')),'') IS NULL THEN
        reason := 'check size amount_text is required (source excerpt, not shown)';
      END IF;
      IF reason IS NULL AND fact ? 'min_usd' AND fact->'min_usd' <> 'null'::jsonb AND btrim(coalesce(fact->>'min_usd','')) !~ '^[1-9][0-9]*$' THEN
        reason := 'check size min_usd must be a positive whole number of US dollars';
      END IF;
      IF reason IS NULL AND fact ? 'max_usd' AND fact->'max_usd' <> 'null'::jsonb AND btrim(coalesce(fact->>'max_usd','')) !~ '^[1-9][0-9]*$' THEN
        reason := 'check size max_usd must be a positive whole number of US dollars';
      END IF;
      IF reason IS NULL AND nullif(btrim(coalesce(fact->>'min_usd','')),'') IS NULL AND nullif(btrim(coalesce(fact->>'max_usd','')),'') IS NULL THEN
        reason := 'check size needs min_usd or max_usd';
      END IF;
      IF reason IS NULL AND nullif(btrim(coalesce(fact->>'min_usd','')),'') IS NOT NULL AND nullif(btrim(coalesce(fact->>'max_usd','')),'') IS NOT NULL AND (btrim(fact->>'min_usd'))::numeric > (btrim(fact->>'max_usd'))::numeric THEN
        reason := 'check size min_usd is greater than max_usd';
      END IF;
    END IF;$old$;
  new := $new$    IF reason IS NULL AND tbl = 'v2_firm_check_sizes' AND NOT (fact ? 'read_on') AND coalesce(fact->>'source_date','') <> '' THEN
      fact := fact || jsonb_build_object('read_on', fact->>'source_date');
    END IF;$new$;
  if position(old in d) = 0 then
    raise notice 'v2_research_submit check size bounds already absent';
    return;
  end if;
  n := replace(d, old, new);
  if n = d or position('check size needs min_usd or max_usd' in n) > 0 then
    raise exception 'v2_research_submit: check size bounds undo did not apply';
  end if;
  execute n;
end
$mig$;
