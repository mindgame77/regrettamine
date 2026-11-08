-- A bare year on a v2 deal ('2026') is stored as January 1 of that year
-- with the existing deal_date_precision 'year'. No new table or column.
-- v2_firm_page is not changed. CI has no v2 schema and skips this.
do $mig$
declare
  d text;
  n text;
  old text;
  new text;
begin
  if to_regprocedure('public.v2_research_submit(uuid,jsonb,boolean)') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;
  select pg_get_functiondef('public.v2_research_submit(uuid,jsonb,boolean)'::regprocedure) into d;
  if position('bare year stored as January 1' in d) > 0 then
    raise notice 'v2_research_submit already accepts a bare year';
    return;
  end if;
  old := $old$    IF reason IS NULL THEN
      IF (p->>'source_level') = '4' THEN p := p || '{"archived":true,"archive_reason":"L4 kept archived (R2)"}'; END IF;$old$;
  new := $new$    IF reason IS NULL AND tbl = 'v2_deals' AND btrim(coalesce(p->>'deal_date','')) ~ '^\d{4}$' THEN
      -- bare year stored as January 1 with the existing precision. The page shows the year only.
      p := p || jsonb_build_object('deal_date', btrim(p->>'deal_date') || '-01-01', 'deal_date_precision', 'year');
    END IF;
    IF reason IS NULL THEN
      IF (p->>'source_level') = '4' THEN p := p || '{"archived":true,"archive_reason":"L4 kept archived (R2)"}'; END IF;$new$;
  if position(old in d) = 0 then
    raise exception 'v2_research_submit: year-only deal anchor missing';
  end if;
  n := replace(d, old, new);
  if n = d or position('bare year stored as January 1' in n) = 0 or position('v2_firm_page' in n) <> position('v2_firm_page' in d) then
    raise exception 'v2_research_submit: bare year patch did not apply';
  end if;
  execute n;
end
$mig$;
