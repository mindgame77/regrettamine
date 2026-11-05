-- a16z (firm_id 2): legal case_type fill (LG2.1), Active status confirm, press tone + legal
-- case_type on v2_firm_page (G4.1 / LG2.1), apply_link on contacts (G1.1 / F4.9).
-- News tones already set in v2_news_items (4 green / 47 grey / 2 red); this only exposes tone
-- through v2_firm_page. Phone left null: Form ADV lists (650) 798-5800 but v2_firm_contacts
-- requires source_level = 2 (firm website only, F4.9); phone not found on a16z.com.
-- LP line format left unchanged (visible design needs a mockup first).
-- The v2 schema is not created by repo migrations; missing objects => no-op.
do $m$
declare
  d text;
  n text;
  v_batch bigint;
  v_sub bigint;
begin
  if to_regclass('public.v2_legal_items') is not null then
    -- LG2.1 case_type from court records. Think Computer: Lanham Act false advertising / UCL -> IP.
    -- Patrzalek: civil RICO complaint (18 U.S.C. 1961) alleging fraud/racketeering -> Fraud.
    -- Teman: COUNT II Fraud (and RICO) in the SDNY complaint -> Fraud.
    update v2_legal_items
       set case_type = 'IP'
     where firm_id = 2 and legal_item_id = 4 and is_current and not archived
       and case_type is null;

    update v2_legal_items
       set case_type = 'Fraud'
     where firm_id = 2 and legal_item_id = 5 and is_current and not archived
       and case_type is null;

    update v2_legal_items
       set case_type = 'Fraud'
     where firm_id = 2 and legal_item_id = 6 and is_current and not archived
       and case_type is null;

    -- Active cases (Samuels, Houghton): status already Active from prior load; keep idempotent.
    update v2_legal_items
       set status = 'Active'
     where firm_id = 2 and legal_item_id in (9, 10) and is_current and not archived
       and status is distinct from 'Active';
  end if;

  if to_regclass('public.v2_firm_contacts') is not null then
    -- G1.1 / F4.9: firm apply page on a16z speedrun subdomain (linked from a16z.com/speedrun/).
    -- Archive the current contacts row and insert a replacement that keeps the email and adds apply_link.
    if exists (
      select 1 from v2_firm_contacts
       where firm_id = 2 and is_current and not archived and not nothing_found
         and apply_link is null
    ) then
      v_batch := (select coalesce(max(batch_id), 0) + 1 from v2_research_submissions);

      insert into v2_research_submissions (batch_id, firm_id, bot_key_id, target_box, payload, status)
      values (v_batch, 2, 3, 'F4',
        jsonb_build_object(
          'target_table', 'v2_firm_contacts',
          'source_owner', 'grok-bot-a16z',
          'origin', 'G1.1 apply_link from a16z speedrun apply page; email carried from offices page',
          'fact', jsonb_build_object(
            'firm_id', '@firm:a16z',
            'contact_email', 'menlopark-info@a16z.com',
            'apply_link', 'https://speedrun.a16z.com/apply',
            'source_url', 'https://speedrun.a16z.com/apply',
            'source_date', '2026-11-04',
            'source_type', 'Firm website',
            'source_level', 2)),
        'Accepted')
      returning submission_id into v_sub;

      update v2_firm_contacts
         set is_current = false,
             archived = true,
             archive_reason = 'replaced: apply_link filled from speedrun.a16z.com/apply'
       where firm_id = 2 and is_current and not archived;

      insert into v2_firm_contacts (
        source_url, source_level, source_date, source_date_precision, source_type,
        source_owner, is_current, submission_id, firm_id,
        contact_email, contact_phone, apply_link
      ) values (
        'https://speedrun.a16z.com/apply', 2, date '2026-11-04', 'full date', 'Firm website',
        'grok-bot-a16z', true, v_sub, 2,
        'menlopark-info@a16z.com', null, 'https://speedrun.a16z.com/apply'
      );
    end if;
  end if;

  if to_regprocedure('public.v2_firm_page(text)') is null then
    raise notice 'v2_firm_page missing, skipped function patch';
    return;
  end if;

  select pg_get_functiondef('public.v2_firm_page(text)'::regprocedure) into d;

  -- G4.1: pass news tone through to the page (green/red/grey).
  n := replace(d,
    $q$'url',n.source_url,'date',to_char(n.published_date,'Mon FMDD, YYYY'),'head',n.headline,'outlet',n.outlet,
      'src',_v2_src(n.source_url,n.published_date,n.outlet)$q$,
    $q$'url',n.source_url,'date',to_char(n.published_date,'Mon FMDD, YYYY'),'head',n.headline,'outlet',n.outlet,'tone',n.tone,
      'src',_v2_src(n.source_url,n.published_date,n.outlet)$q$);

  -- LG2.1: pass case_type so the topic pill can draw (legalCase reads about || case_type).
  n := replace(n,
    $q$'role',l.side,'tone',null,'year',l.filed_year::text,'state',l.status,$q$,
    $q$'role',l.side,'tone',null,'about',l.case_type,'case_type',l.case_type,'year',l.filed_year::text,'state',l.status,$q$);

  if n = d then
    raise notice 'v2_firm_page already patched or placeholders missing';
  else
    execute n;
  end if;
end $m$;
