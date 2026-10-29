-- Delete and restore for the five SEC adviser summary rows.
-- Alex approved the delete at 2:28 PM PT on Oct 29, 2026 (owner message t2894u): Yes, delete.
-- The delete below was run that day. Exactly these five firm_legal_items rows, and their five fact_sources rows, were removed.
-- The Mio Partners SEC action (id 0423628e-8b51-5095-a1a0-86409ff438ee) is not in this list.
-- The copy of the rows is supabase/rollbacks/20261029320000_fix5_sec_summary_export.json.
-- That copy is not loaded into the database.
--
-- To put the five rows back, run the restore block and change the final rollback to commit.
-- The summary guard drops a plain insert, so the restore turns that trigger off for these inserts and turns it back on.
-- stable_key is generated from the title (_legal_key). The insert leaves it out. The export file still has the old value.
-- The restore block was proved inside a rolled-back transaction on 2026-10-29. It ends with rollback so running this file does not put the rows back.

-- Delete. Already applied.
begin;
delete from public.fact_sources
 where fact_type = 'firm_legal_items' and fact_id in (
'5472859e-1488-a40e-c4cb-f98a46a6b3af',
'41a8d87f-c6d6-8a47-0dc3-c0e4fbdb73c0',
'95b4a2d3-0734-c461-45a3-6faf1d2acf46',
'b234b35f-5e9d-52e4-7bb8-839bdcc21966',
'42ed7a0e-7ffc-0f46-e31d-be903d1dd585'
 );
delete from public.firm_legal_items
 where id in (
'5472859e-1488-a40e-c4cb-f98a46a6b3af',
'41a8d87f-c6d6-8a47-0dc3-c0e4fbdb73c0',
'95b4a2d3-0734-c461-45a3-6faf1d2acf46',
'b234b35f-5e9d-52e4-7bb8-839bdcc21966',
'42ed7a0e-7ffc-0f46-e31d-be903d1dd585'
 );
commit;

-- Restore. Ends with rollback. Change that line to commit only when the five rows should come back.
begin;
-- RESTORE_BODY_BEGIN
alter table public.firm_legal_items disable trigger sec_summary_guard;

insert into public.firm_legal_items (
  id, firm_id, grp, title, year_label, role, state, status_label, tone, note,
  sort_order, hidden, hidden_reason, hidden_at, hidden_by,
  last_checked_at, checked_source, checked_on, checked_by, source_level,
  summary, summary_date, summary_source_url, summary_by
) values
  ('41a8d87f-c6d6-8a47-0dc3-c0e4fbdb73c0'::uuid, 'f7859242-8697-5a7d-aa2f-e3bf52f6f8f0'::uuid, 'regulator', $title$IAPD/FINRA firm IA disclosure flag = N. Registered investment adviser GREENOAKS, SEC 801-88209, which counts as Clear. Principal office SAN FRANCISCO California United States 94129. Item 5F regulatory AUM $18,272,992,245. Schedule A: Peretz, Benjamin, Scott (Managing Partner, 04/2012); Mehta, Neil (Managing Partner, 04/2012); Lai, Patrick, Heining (Chief Financial Officer, 07/2017); Schrier, Benjamin, Woodside (General Counsel, 04/2022); Keenan, Lindsey, Taylor (Chief Compliance Officer, 07/2026). https://adviserinfo.sec.gov/firm/summary/165941$title$, '2012', null, null, null, null, null, 512, false, null, null, null, null, null, null, null, null, null, null, null, null),
  ('42ed7a0e-7ffc-0f46-e31d-be903d1dd585'::uuid, 'aa203948-726d-453c-bc0c-55d4ef1eecaa'::uuid, 'regulator', $title$IAPD/FINRA firm IA disclosure flag = N. Registered investment adviser SEQUOIA CAPITAL OPERATIONS, LLC, SEC 801-122957, which counts as Clear. Principal office MENLO PARK California United States 94025-7055. Item 5F regulatory AUM $82,165,771,068. Schedule A: Leone, Douglas, Mauro (Managing Member, 01/2003); Goetz, James, J. (Managing Member, 06/2018); Lin, Alfred, Nmn (Managing Member, 09/2012); Grady, Patrick, William (Managing Member, 05/2013); Klemchuk, Marie, Louise (Chief Financial Officer, 03/2016); Son, Jung, Yeon (Chief Legal Officer And Chief Compliance Officer, 10/2019); Reed, Andrew$title$, '2003', null, null, null, null, null, 511, false, null, null, null, null, null, null, null, null, null, null, null, null),
  ('5472859e-1488-a40e-c4cb-f98a46a6b3af'::uuid, '02f0cd7f-dbfd-4412-9a90-8326ccdd6132'::uuid, 'regulator', $title$IAPD/FINRA firm IA disclosure flag = N. Registered investment adviser GENERAL CATALYST, SEC 801-115155, which counts as Clear. Principal office CAMBRIDGE Massachusetts United States 02138. Item 5F regulatory AUM $45,502,659,880. Schedule A: Taneja, Hemant, Nmn (Managing Director, 01/2012); Mccain, Christopher, Luke (Chief Legal Officer, 10/2015); Allen, Mark, Joseph (Head Of Fund Operations, 08/2024); Chenault, Kenneth, Irvine (Managing Director, 02/2018); Dell, Anthony, Stanton (Chief Compliance Officer, 09/2018); Gc Management Partners, Lp (Member, 11/2018); Fielding, Paul, Sanford (Chief Fi$title$, '2012', null, null, null, null, null, 507, false, null, null, null, null, null, null, null, null, null, null, null, null),
  ('95b4a2d3-0734-c461-45a3-6faf1d2acf46'::uuid, '77eb2759-5255-4bdf-a345-fc077f12ab80'::uuid, 'regulator', $title$IAPD/FINRA firm IA disclosure flag = N. Registered investment adviser LIGHTSPEED VENTURE PARTNERS, SEC 801-132552, which counts as Clear. Principal office MENLO PARK California United States 94025. Item 5F regulatory AUM $50,005,412,721. Schedule A: Eggers, Barry, Francis (Member, 08/2005); Mhatre, Ravi, Brian (Member, 08/2005); Nieh, Peter, Yao-Ping (Member, 08/2005); Schaepe, Christopher, James (Member, 08/2005); Somaia, Bejul, Pradip (Member, 01/2025); Connor, Ryan, Jonathan (Chief Financial Officer, 03/2025); Adams, Jessica, Ashley (Chief Compliance Officer And Counsel, 07/2024); Nissenber$title$, '2005', null, null, null, null, null, 506, false, null, null, null, null, null, null, null, null, null, null, null, null),
  ('b234b35f-5e9d-52e4-7bb8-839bdcc21966'::uuid, '40f97e7b-57a8-5f00-8262-ba7cf7ff7f91'::uuid, 'regulator', $title$IAPD/FINRA firm IA disclosure flag = Y. Registered investment adviser MIO PARTNERS, INC., SEC 801-41495, which counts as Clear. Principal office NEW YORK New York United States 10111. Item 5F regulatory AUM $59,588,224,670. Schedule A: Mio Group, Inc. (Shareholder, 07/2003); Lipscomb, Casey, Sinclair (General Counsel And Secretary, 12/2004); Orr, Gordon, Robert Halyburton (Director, 06/2008); Kelly, Matthew, Charles (Chief Financial Officer, 01/2014); Daruvala, Toos, Noshir (Director, 04/2021); Flynn, Timothy, Patrick (Director, 11/2017); Cumming, Christine, Maureen (Director, 11/2017); Patsal$title$, '2003', null, null, null, null, null, 506, false, null, null, null, null, null, null, null, null, null, null, null, null);

insert into public.fact_sources (
  id, source_id, firm_id, fact_type, fact_id, label, sort_order,
  created_at, updated_at, data_status, date_label
) values
  ('4df423a4-dcbf-b24d-639f-8ed4bea2f9ed'::uuid, '5f8cfd9c-386e-42f3-834a-48bc5b7187cc'::uuid, 'f7859242-8697-5a7d-aa2f-e3bf52f6f8f0'::uuid, 'firm_legal_items', '41a8d87f-c6d6-8a47-0dc3-c0e4fbdb73c0'::uuid, 'adviserinfo.sec.gov', 0, '2026-10-24T17:58:17.009099+00:00'::timestamptz, '2026-10-26T06:39:32.266495+00:00'::timestamptz, 'real'::public.data_status, '2026-10-24'),
  ('411d1a09-5c9e-5da0-4ae5-6e6c67a2180f'::uuid, 'debbac33-69db-4a93-a4ed-80366b1d04a8'::uuid, 'aa203948-726d-453c-bc0c-55d4ef1eecaa'::uuid, 'firm_legal_items', '42ed7a0e-7ffc-0f46-e31d-be903d1dd585'::uuid, 'adviserinfo.sec.gov', 0, '2026-10-24T20:32:57.485438+00:00'::timestamptz, '2026-10-26T06:39:20.665468+00:00'::timestamptz, 'real'::public.data_status, '2026-10-24'),
  ('3766b13e-5441-675f-b501-c8c8f91f5a58'::uuid, '21689c2c-89cb-48e4-8bf0-2c8e8c7be8b0'::uuid, '02f0cd7f-dbfd-4412-9a90-8326ccdd6132'::uuid, 'firm_legal_items', '5472859e-1488-a40e-c4cb-f98a46a6b3af'::uuid, 'adviserinfo.sec.gov', 0, '2026-10-24T20:26:26.659623+00:00'::timestamptz, '2026-10-26T06:39:09.347575+00:00'::timestamptz, 'real'::public.data_status, '2026-10-24'),
  ('1fd18937-b9f5-d07a-2443-910e0ee17084'::uuid, 'a8ea47e5-16ca-4059-b68a-a0ba0b2dacdb'::uuid, '77eb2759-5255-4bdf-a345-fc077f12ab80'::uuid, 'firm_legal_items', '95b4a2d3-0734-c461-45a3-6faf1d2acf46'::uuid, 'adviserinfo.sec.gov', 0, '2026-10-24T20:29:01.27097+00:00'::timestamptz, '2026-10-26T06:39:09.347575+00:00'::timestamptz, 'real'::public.data_status, '2026-10-24'),
  ('21d062ca-a679-4bb7-09af-99c75e3ea2ee'::uuid, '8cbc6f95-fcb3-48b8-ae8f-f8b0c69a83d4'::uuid, '40f97e7b-57a8-5f00-8262-ba7cf7ff7f91'::uuid, 'firm_legal_items', 'b234b35f-5e9d-52e4-7bb8-839bdcc21966'::uuid, 'adviserinfo.sec.gov', 0, '2026-10-24T17:58:17.009099+00:00'::timestamptz, '2026-10-26T06:41:00.901784+00:00'::timestamptz, 'real'::public.data_status, '2026-10-24');

alter table public.firm_legal_items enable trigger sec_summary_guard;
-- RESTORE_BODY_END
rollback;
