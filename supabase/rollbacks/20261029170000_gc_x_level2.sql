-- Rollback for 20261029170000_gc_x_level2.sql: back to no level (pill hidden).
update public.vc_source_facts
   set source_level = null, value = value - 'linked_from' - 'linked_checked'
 where id = '2bf03a81-c8a9-5bb9-863d-8f7291ca62a3';
