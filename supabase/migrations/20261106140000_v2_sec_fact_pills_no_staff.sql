-- Drop Staff and Investment staff from v2_sec_fact_pills. Private funds stays.
-- The v2 schema is not created by repo migrations. On a database without the table (CI) this is a no-op.
-- Undo: supabase/rollbacks/20261106140000_v2_sec_fact_pills_no_staff.sql
-- Deleted pill rows are not restored by the undo.
do $mig$
declare
  d text;
  n text;
  staff_in text := $old$fact_label in ('Staff','Investment staff')$old$;
  funds_in text := $new$fact_label in ('Private funds')$new$;
  staff_note text := $old$SEC Form ADV Staff / Investment staff counts (Private funds left out, per approved mockup)$old$;
  funds_note text := $new$Private funds count only. Staff and Investment staff are not published$new$;
  review_anchor text := $old$    -- G5.2 (Alex 2026-11-04 12:40 PM PT): a review's reviewer_role / reviewer_company needs a valid reviewer_role_source_url$old$;
  staff_reject text := $new$    IF reason IS NULL AND tbl = 'v2_sec_fact_pills' AND lower(btrim(coalesce(fact->>'fact_label',''))) IN ('staff','investment staff') THEN
      reason := 'Staff and Investment staff are not accepted';
    END IF;
$new$;
begin
  if to_regclass('public.v2_sec_fact_pills') is null then
    raise notice 'v2_sec_fact_pills missing, skipped';
    return;
  end if;

  delete from public.v2_sec_fact_pills
   where lower(btrim(fact_label)) in ('staff', 'investment staff');

  if not exists (
    select 1 from pg_constraint
     where conname = 'v2_sec_fact_pills_no_staff_labels'
       and conrelid = 'public.v2_sec_fact_pills'::regclass
  ) then
    alter table public.v2_sec_fact_pills
      add constraint v2_sec_fact_pills_no_staff_labels
      check (lower(btrim(fact_label)) not in ('staff', 'investment staff'));
  end if;

  if to_regprocedure('public.v2_firm_page(text)') is not null then
    select pg_get_functiondef('public.v2_firm_page(text)'::regprocedure) into d;
    if position(staff_in in d) > 0 then
      n := replace(d, staff_in, funds_in);
      n := replace(n, staff_note, funds_note);
      if position(funds_in in n) = 0 or position(staff_in in n) > 0 then
        raise exception 'v2_firm_page: Staff pill select was not replaced';
      end if;
      execute n;
    elsif position(funds_in in d) = 0 then
      raise exception 'v2_firm_page: Staff pill select not found';
    end if;
  end if;

  if to_regprocedure('public.v2_research_submit(uuid,jsonb,boolean)') is not null then
    select pg_get_functiondef('public.v2_research_submit(uuid,jsonb,boolean)'::regprocedure) into d;
    if position('Staff and Investment staff are not accepted' in d) = 0 then
      if position(review_anchor in d) = 0 then
        raise exception 'v2_research_submit: staff reject anchor not found';
      end if;
      n := replace(d, review_anchor, staff_reject || review_anchor);
      if position('Staff and Investment staff are not accepted' in n) = 0 then
        raise exception 'v2_research_submit: staff reject was not inserted';
      end if;
      execute n;
    end if;
  end if;
end
$mig$;
