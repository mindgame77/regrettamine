-- Investor quotes only: published_at may be empty. A missing date is stored as null and is not rejected.
-- Other fact types keep their date rules. The v2 schema is not created by repo migrations; CI skips this.
do $mig$
declare
  d text;
  n text;
  old text;
  new text;
begin
  if to_regclass('public.v2_investor_principles') is not null then
    execute 'alter table public.v2_investor_principles alter column published_at drop not null';
  end if;

  if to_regprocedure('public.v2_research_submit(uuid,jsonb,boolean)') is null then
    raise notice 'v2_research_submit missing, skipped';
    return;
  end if;

  select pg_get_functiondef('public.v2_research_submit(uuid,jsonb,boolean)'::regprocedure) into d;
  if position('fact := fact - ''published_at''' in d) > 0 then
    raise notice 'v2_research_submit quote date already optional';
    return;
  end if;

  old := $old$      ELSIF NOT (fact ? 'display_order') AND fid IS NOT NULL THEN
        fact := fact || jsonb_build_object('display_order', coalesce((SELECT max(pr.display_order) FROM public.v2_investor_principles pr WHERE pr.firm_id = fid), 0) + 1);
      END IF;
    END IF;$old$;
  new := $new$      ELSIF NOT (fact ? 'display_order') AND fid IS NOT NULL THEN
        fact := fact || jsonb_build_object('display_order', coalesce((SELECT max(pr.display_order) FROM public.v2_investor_principles pr WHERE pr.firm_id = fid), 0) + 1);
      END IF;
      IF reason IS NULL AND nullif(btrim(fact->>'published_at'),'') IS NULL THEN
        fact := fact - 'published_at';
      END IF;
    END IF;$new$;
  if position(old in d) = 0 then
    raise exception 'v2_research_submit: quote date anchor missing';
  end if;
  n := replace(d, old, new);
  if n = d or position('fact := fact - ''published_at''' in n) = 0 then
    raise exception 'v2_research_submit: quote date patch did not apply';
  end if;
  execute n;
end
$mig$;
