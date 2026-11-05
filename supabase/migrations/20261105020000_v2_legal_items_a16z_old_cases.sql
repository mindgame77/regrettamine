-- a16z (v2 firm 2): move old public.firm_legal_items cases that pass LG1-LG3 into v2_legal_items.
-- Each row was checked against the court record (RECAP copies of PACER filings on archive.org).
-- The v2 schema is not created by repo migrations; on a database without v2_legal_items (CI) this is a no-op.
-- Idempotent: a case is skipped when firm 2 already has a row with the same court.
do $$
declare
  v_batch bigint;
  r record;
  v_sub bigint;
  v_li bigint;
begin
  if to_regclass('public.v2_legal_items') is null then raise notice 'v2 schema missing, skipped'; return; end if;
  v_batch := (select coalesce(max(batch_id), 0) + 1 from v2_research_submissions);
  for r in
    select * from (values
      ('Active', 'Andrew Samuels', 2023::smallint, null::smallint, 'N.D. Cal. 3:23-cv-06492',
       'https://archive.org/download/gov.uscourts.cand.422388/gov.uscourts.cand.422388.203.0.pdf', date '2026-06-18',
       'Lido token buyers'' class action naming AH Capital Management (a16z) as a defendant under Securities Act Section 12(a)(1). The court denied the defendants'' motion to compel arbitration; a16z and others appealed to the Ninth Circuit in Sept 2025, still pending in June 2026.'),
      ('Active', 'Amanda Houghton', 2022::smallint, null::smallint, 'N.D. Cal. 3:22-cv-07781',
       'https://archive.org/download/gov.uscourts.cand.404947/gov.uscourts.cand.404947.327.0.pdf', date '2026-09-01',
       'Compound token buyers'' class action naming AH Capital Management (a16z) as a defendant under Securities Act Section 12(a)(1). In Sept 2026 the parties reported an agreement in principle to settle as to a16z and Paradigm; plaintiffs were preparing a motion for court approval.'),
      ('Dismissed', 'Nessa Risley', 2022::smallint, 2025::smallint, 'S.D.N.Y. 1:22-cv-02780; 2d Cir. 23-1340',
       'https://archive.org/download/gov.uscourts.ca2.61076/gov.uscourts.ca2.61076.114.0.pdf', date '2025-02-26',
       'Uniswap token buyers'' class action naming AH Capital Management (a16z) as a defendant. Federal securities claims were dismissed in 2023; on Feb 26, 2025 the Second Circuit affirmed that dismissal and sent only state-law claims back to the district court.')
    ) as t(status, other_party, filed_year, closed_year, court, url, src_date, summary)
  loop
    continue when exists (select 1 from v2_legal_items where firm_id = 2 and court = r.court);

    insert into v2_research_submissions (batch_id, firm_id, bot_key_id, target_box, payload, status)
    values (v_batch, 2, 3, 'F20',
      jsonb_build_object(
        'target_table', 'v2_legal_items',
        'source_owner', 'grok-bot-a16z',
        'origin', 'moved from public.firm_legal_items after LG1-LG3 check against the court record',
        'fact', jsonb_build_object('firm_id', '@firm:a16z', 'item_group', 'case', 'status', r.status,
          'side', 'Defendant', 'case_type', 'Securities', 'other_party', r.other_party,
          'filed_year', r.filed_year, 'closed_year', r.closed_year, 'court', r.court,
          'source_url', r.url, 'source_date', r.src_date, 'source_type', 'Court record', 'source_level', 1)),
      'Accepted')
    returning submission_id into v_sub;

    insert into v2_legal_items (source_url, source_level, source_date,
      source_date_precision, source_type, source_owner, is_current, submission_id, firm_id, item_group,
      status, side, case_type, other_party, filed_year, closed_year, court,
      case_summary, summary_date, summary_source_url)
    values (r.url, 1, r.src_date,
      'full date', 'Court record', 'grok-bot-a16z', true, v_sub, 2, 'case',
      r.status, 'Defendant', 'Securities', r.other_party, r.filed_year, r.closed_year, r.court,
      left(r.summary, 300), r.src_date, r.url)
    returning legal_item_id into v_li;
  end loop;
end $$;
