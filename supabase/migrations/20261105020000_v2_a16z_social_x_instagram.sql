-- F11: a16z (firm_id 2) X and Instagram counts, L2, read 2026-11-04 from each account; both linked from a16z.com (re-checked 2026-11-04).
-- X: exact count from X's API for @a16z. Instagram: public profile shows "228K followers" (no login) -> 228000, is_rounded.
-- Instagram latest post date could not be read publicly (no-login page and web_profile_info JSON blocked), so it is left empty (F11.8.1: shown grey).
-- Legacy X row 5 (no count) archived. On a database without the v2 schema (CI) this is a no-op.
do $m$ declare sub bigint; begin
  if to_regclass('public.v2_social_accounts') is null then raise notice 'v2 schema missing, skipped'; return; end if;

  update v2_social_accounts set archived = true, archive_reason = 'replaced by 2026-11-04 read'
   where firm_id = 2 and row_id = 5 and not archived;

  select submission_id into sub from v2_social_accounts where row_id = 5;
  insert into v2_social_accounts (firm_id, platform, account_url, follower_count, is_rounded, date_read, latest_post_date, latest_post_link,
     source_url, source_level, source_date, source_type, source_owner, is_current, submission_id, unlinked_or_dead_mark)
  values (2,'X','https://x.com/a16z',1104420,false,'2026-11-04','2026-11-04',
     'https://x.com/a16z/status/2118123637735919725',
     'https://x.com/a16z',2,'2026-11-04','Social post','grok-bot',true,sub,'none');

  insert into v2_research_submissions (batch_id, firm_id, bot_key_id, target_box, payload, status)
  values (1029, 2, 7, 'F27', jsonb_build_object('ref',null,'firm_ref',null,'source_owner','grok-bot','target_table','v2_social_accounts',
     'origin','linked from a16z.com; ''228K followers'' on public profile (no login) 2026-11-04; latest post date not readable publicly',
     'fact',jsonb_build_object('platform','Instagram','account_url','https://www.instagram.com/a16z/','source_url','https://www.instagram.com/a16z/',
       'follower_count',228000,'date_read','2026-11-04','source_date','2026-11-04','source_type','Social post','source_level',2,
       'source_date_precision','full date','source_date_is_found_date',true)), 'Accepted')
  returning submission_id into sub;
  insert into v2_social_accounts (firm_id, platform, account_url, follower_count, is_rounded, date_read, latest_post_date, latest_post_link,
     source_url, source_level, source_date, source_type, source_owner, is_current, submission_id, unlinked_or_dead_mark)
  values (2,'Instagram','https://www.instagram.com/a16z/',228000,true,'2026-11-04',null,null,
     'https://www.instagram.com/a16z/',2,'2026-11-04','Social post','grok-bot',true,sub,'none');
end $m$;
