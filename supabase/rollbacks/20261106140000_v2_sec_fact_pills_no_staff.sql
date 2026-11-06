-- Undo 20261106140000_v2_sec_fact_pills_no_staff.
-- Restores the publish and research checks. Does not put deleted Staff or Investment staff rows back.
do $undo$
declare
  d text;
  n text;
  staff_in text := $old$fact_label in ('Staff','Investment staff')$old$;
  funds_in text := $new$fact_label in ('Private funds')$new$;
  staff_note text := $old$SEC Form ADV Staff / Investment staff counts (Private funds left out, per approved mockup)$old$;
  funds_note text := $new$Private funds count only. Staff and Investment staff are not published$new$;
  staff_reject text := $new$    IF reason IS NULL AND tbl = 'v2_sec_fact_pills' AND lower(btrim(coalesce(fact->>'fact_label',''))) IN ('staff','investment staff') THEN
      reason := 'Staff and Investment staff are not accepted';
    END IF;
$new$;
begin
  if to_regclass('public.v2_sec_fact_pills') is null then
    raise notice 'v2_sec_fact_pills missing, skipped';
    return;
  end if;

  alter table public.v2_sec_fact_pills drop constraint if exists v2_sec_fact_pills_no_staff_labels;

  if to_regprocedure('public.v2_firm_page(text)') is not null then
    select pg_get_functiondef('public.v2_firm_page(text)'::regprocedure) into d;
    if position(funds_in in d) > 0 and position(funds_note in d) > 0 then
      n := replace(d, funds_in, staff_in);
      n := replace(n, funds_note, staff_note);
      execute n;
    end if;
  end if;

  if to_regprocedure('public.v2_research_submit(uuid,jsonb,boolean)') is not null then
    select pg_get_functiondef('public.v2_research_submit(uuid,jsonb,boolean)'::regprocedure) into d;
    if position(staff_reject in d) > 0 then
      n := replace(d, staff_reject, '');
      execute n;
    end if;
  end if;
end
$undo$;
