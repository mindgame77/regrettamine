-- Firm header: one published check size on v2_firm_page (firm.check_size).
-- Current published means is_current and not archived, the same gate as stages.
-- The value is amount_text. min_usd, max_usd, program_name, and source_url stay in the table and are not returned.
-- Several current rows: the latest read_on, then the highest id. No row, or a blank amount_text: null.
-- The v2 schema is not created by repo migrations. On a database without v2_firm_page (CI) this is a no-op.
do $mig$
declare
  d text;
  n text;
  old text;
  new text;
begin
  if to_regprocedure('public.v2_firm_page(text)') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;
  if to_regclass('public.v2_firm_check_sizes') is null then
    raise exception 'v2_firm_page exists but v2_firm_check_sizes is missing';
  end if;

  select pg_get_functiondef('public.v2_firm_page(text)'::regprocedure) into d;
  if position($a$'check_size',(select nullif(btrim(c.amount_text),'') from v2_firm_check_sizes c$a$ in d) > 0 then
    raise notice 'v2_firm_page check size already patched';
    return;
  end if;

  old := $old$from v2_firm_stages s where s.firm_id=fid and s.is_current and not s.archived),'[]'::json),
       'contact_email'$old$;
  new := $new$from v2_firm_stages s where s.firm_id=fid and s.is_current and not s.archived),'[]'::json),
       'check_size',(select nullif(btrim(c.amount_text),'') from v2_firm_check_sizes c where c.firm_id=fid and c.is_current and not c.archived and nullif(btrim(c.amount_text),'') is not null order by c.read_on desc nulls last, c.id desc limit 1),
       'contact_email'$new$;
  if position(old in d) = 0 then
    raise exception 'v2_firm_page: stages anchor missing';
  end if;
  n := replace(d, old, new);
  if n = d or position($a$'check_size',(select nullif(btrim(c.amount_text),'') from v2_firm_check_sizes c$a$ in n) = 0 then
    raise exception 'v2_firm_page: check size patch did not apply';
  end if;
  execute n;
end
$mig$;
