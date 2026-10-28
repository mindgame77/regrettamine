-- Undoes the one-home write. Puts backed-up rows back. Does not delete home_merge_backup.
-- home_merge_log rows from this step are removed. Old tables are not dropped.

insert into public.press_items
select rec.* from public.home_merge_backup b,
  lateral jsonb_populate_record(null::public.press_items, b.row_data) rec
where b.table_name = 'press_items'
on conflict (id) do nothing;

insert into public.press_item_firms
select rec.* from public.home_merge_backup b,
  lateral jsonb_populate_record(null::public.press_item_firms, b.row_data) rec
where b.table_name = 'press_item_firms'
on conflict (press_item_id, firm_id) do nothing;

insert into public.timeline_events
select rec.* from public.home_merge_backup b,
  lateral jsonb_populate_record(null::public.timeline_events, b.row_data) rec
where b.table_name = 'timeline_events'
on conflict (id) do nothing;

insert into public.firm_people_roles
select rec.* from public.home_merge_backup b,
  lateral jsonb_populate_record(null::public.firm_people_roles, b.row_data) rec
where b.table_name = 'firm_people_roles'
on conflict (id) do nothing;

insert into public.firm_legal_items
select rec.* from public.home_merge_backup b,
  lateral jsonb_populate_record(null::public.firm_legal_items, b.row_data) rec
where b.table_name = 'firm_legal_items'
on conflict (id) do nothing;

insert into public.reviews
select rec.* from public.home_merge_backup b,
  lateral jsonb_populate_record(null::public.reviews, b.row_data) rec
where b.table_name = 'reviews'
on conflict (id) do nothing;

insert into public.funds
select rec.* from public.home_merge_backup b,
  lateral jsonb_populate_record(null::public.funds, b.row_data) rec
where b.table_name = 'funds'
on conflict (id) do nothing;

delete from public.conflict_weekly where reason like 'home merge:%';
delete from public.publish_checks where reason like 'home merge:%';
delete from public.home_merge_log where detail is not null;

drop function if exists public.lab_one_home(boolean);
