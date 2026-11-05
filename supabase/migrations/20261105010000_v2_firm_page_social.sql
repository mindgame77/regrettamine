-- F11: v2_firm_page returns firm.social from v2_social_accounts (current, not archived, count read within 12 months, F11.7.2).
-- Loads a16z (firm_id 2) counts read on 2026-11-04 from each account's own public page; every account is linked from a16z.com.
-- X and Instagram: linked from a16z.com, but the public page does not show a follower count without sign-in, so no row (never guessed).
-- The v2 schema is not created by repo migrations; on a database without v2_firm_page (CI) this is a no-op.
do $m$ declare d text; n text; sub bigint; begin
  if to_regprocedure('public.v2_firm_page(text)') is null then raise notice 'v2 schema missing, skipped'; return; end if;

  update v2_social_accounts set archived = true, archive_reason = 'replaced by 2026-11-04 read'
   where firm_id = 2 and row_id in (6,7,8) and not archived;

  select submission_id into sub from v2_social_accounts where row_id = 6;
  insert into v2_social_accounts (firm_id, platform, account_url, follower_count, is_rounded, date_read, latest_post_date, latest_post_link,
     source_url, source_level, source_date, source_type, source_owner, is_current, submission_id, unlinked_or_dead_mark)
  values (2,'LinkedIn','https://www.linkedin.com/company/a16z',785261,false,'2026-11-04','2026-11-04',
     'https://www.linkedin.com/posts/a16z_build-something-people-want-activity-7523849042875854849-VM4c',
     'https://www.linkedin.com/company/a16z',2,'2026-11-04','Social post','grok-bot',true,sub,'none');
  select submission_id into sub from v2_social_accounts where row_id = 7;
  insert into v2_social_accounts (firm_id, platform, account_url, follower_count, is_rounded, date_read, latest_post_date, latest_post_link,
     source_url, source_level, source_date, source_type, source_owner, is_current, submission_id, unlinked_or_dead_mark)
  values (2,'Substack','https://a16z.substack.com',281000,false,'2026-11-04','2026-11-04',
     'https://a16z.substack.com/p/is-private-equity-cooked',
     'https://a16z.substack.com',2,'2026-11-04','Social post','grok-bot',true,sub,'none');
  select submission_id into sub from v2_social_accounts where row_id = 8;
  insert into v2_social_accounts (firm_id, platform, account_url, follower_count, is_rounded, date_read, latest_post_date, latest_post_link,
     source_url, source_level, source_date, source_type, source_owner, is_current, submission_id, unlinked_or_dead_mark)
  values (2,'YouTube','https://www.youtube.com/@a16z',307000,true,'2026-11-04','2026-11-04',
     'https://www.youtube.com/watch?v=dSiTwPl0t1U',
     'https://www.youtube.com/@a16z',2,'2026-11-04','Social post','grok-bot',true,sub,'none');

  select pg_get_functiondef('public.v2_firm_page(text)'::regprocedure) into d;
  n := replace(d, $q$'social','[]'::json,$q$, $q$'social',coalesce((select json_agg(json_build_object('platform',lower(s.platform),'url',s.account_url,
         'followers',s.follower_count,'is_rounded',s.is_rounded,'date_read',s.date_read,'latest_post_date',s.latest_post_date,
         'latest_post_link',s.latest_post_link,'source_url',s.source_url) order by s.follower_count desc)
         from v2_social_accounts s where s.firm_id=fid and s.is_current and not s.archived and not s.nothing_found
          and s.source_level=2 and s.follower_count is not null and s.date_read >= current_date - interval '12 months'),'[]'::json),$q$);
  if n = d then raise exception 'social placeholder not found in v2_firm_page'; end if;
  execute n;
end $m$;
