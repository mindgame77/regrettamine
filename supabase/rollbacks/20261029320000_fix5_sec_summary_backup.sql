-- NOT RUN. Backup of the five SEC adviser summary rows. Alex has not approved deleting them.
-- Copies the rows and their source links. Does not delete anything.

create schema if not exists backup_fix5_sec_summary;
drop table if exists backup_fix5_sec_summary.fact_sources;
drop table if exists backup_fix5_sec_summary.firm_legal_items;
create table backup_fix5_sec_summary.firm_legal_items as
select i.* from public.firm_legal_items i
 where i.id in (
'5472859e-1488-a40e-c4cb-f98a46a6b3af', -- General Catalyst
'41a8d87f-c6d6-8a47-0dc3-c0e4fbdb73c0', -- Greenoaks
'95b4a2d3-0734-c461-45a3-6faf1d2acf46', -- Lightspeed Venture Partners
'b234b35f-5e9d-52e4-7bb8-839bdcc21966', -- MIO Partners (the IAPD summary, not the SEC action)
'42ed7a0e-7ffc-0f46-e31d-be903d1dd585'  -- Sequoia Capital
 );
alter table backup_fix5_sec_summary.firm_legal_items add primary key (id);
create table backup_fix5_sec_summary.fact_sources as
select fs.* from public.fact_sources fs
 where fs.fact_type = 'firm_legal_items' and fs.fact_id in (
'5472859e-1488-a40e-c4cb-f98a46a6b3af', -- General Catalyst
'41a8d87f-c6d6-8a47-0dc3-c0e4fbdb73c0', -- Greenoaks
'95b4a2d3-0734-c461-45a3-6faf1d2acf46', -- Lightspeed Venture Partners
'b234b35f-5e9d-52e4-7bb8-839bdcc21966', -- MIO Partners (the IAPD summary, not the SEC action)
'42ed7a0e-7ffc-0f46-e31d-be903d1dd585'  -- Sequoia Capital
 );
