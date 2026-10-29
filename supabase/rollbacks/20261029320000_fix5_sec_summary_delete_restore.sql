-- NOT RUN. Delete and restore for the five SEC adviser summary rows only.
-- The next line stops an accidental run. Remove it only when Alex gives the delete words.
do $$ begin raise exception 'not run: Alex has not approved deleting the five SEC adviser summary rows'; end $$;
-- Do not run this until Alex gives the delete words. Run the backup script first.
-- The Mio Partners SEC action (id 0423628e-8b51-5095-a1a0-86409ff438ee) is not in this list.

-- Delete
begin;
delete from public.fact_sources
 where fact_type = 'firm_legal_items' and fact_id in (
'5472859e-1488-a40e-c4cb-f98a46a6b3af', -- General Catalyst
'41a8d87f-c6d6-8a47-0dc3-c0e4fbdb73c0', -- Greenoaks
'95b4a2d3-0734-c461-45a3-6faf1d2acf46', -- Lightspeed Venture Partners
'b234b35f-5e9d-52e4-7bb8-839bdcc21966', -- MIO Partners (the IAPD summary, not the SEC action)
'42ed7a0e-7ffc-0f46-e31d-be903d1dd585'  -- Sequoia Capital
 );
delete from public.firm_legal_items
 where id in (
'5472859e-1488-a40e-c4cb-f98a46a6b3af', -- General Catalyst
'41a8d87f-c6d6-8a47-0dc3-c0e4fbdb73c0', -- Greenoaks
'95b4a2d3-0734-c461-45a3-6faf1d2acf46', -- Lightspeed Venture Partners
'b234b35f-5e9d-52e4-7bb8-839bdcc21966', -- MIO Partners (the IAPD summary, not the SEC action)
'42ed7a0e-7ffc-0f46-e31d-be903d1dd585'  -- Sequoia Capital
 );
commit;

-- Restore (from backup_fix5_sec_summary). Run only after the backup script.
-- begin;
-- insert into public.firm_legal_items select * from backup_fix5_sec_summary.firm_legal_items;
-- insert into public.fact_sources select * from backup_fix5_sec_summary.fact_sources;
-- commit;
