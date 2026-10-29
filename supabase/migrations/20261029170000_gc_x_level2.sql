-- General Catalyst X account is linked from the firm's own website (level 2, A2.10 / B3.8).
-- Rechecked 2026-10-29: https://www.generalcatalyst.com/ links https://x.com/generalcatalyst.
-- Only the level is set; the stored follower count (96980, retrieved 2026-10-12) is unchanged.
-- Rollback: supabase/rollbacks/20261029170000_gc_x_level2.sql
update public.vc_source_facts
   set source_level = 2,
       value = value || jsonb_build_object('linked_from', 'https://www.generalcatalyst.com/', 'linked_checked', '2026-10-29')
 where id = '2bf03a81-c8a9-5bb9-863d-8f7291ca62a3'
   and firm_id = '02f0cd7f-dbfd-4412-9a90-8326ccdd6132'
   and source_url = 'https://x.com/generalcatalyst'
   and value->>'entity' = 'firm';
