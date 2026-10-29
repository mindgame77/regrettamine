-- _firm_social shows only Checker-approved social accounts (level-2 media_reach facts written by the
-- Checker social path, #267). It never reads raw socialAccounts uploads in bots.research_submissions (#256 did).
-- Rollback: supabase/rollbacks/20261029220000_firm_social_checker_only.sql

CREATE OR REPLACE FUNCTION public._firm_social(p_firm uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with ok as (
    select substring(v.value->>'field' from '^media_([a-z]+)_followers$') platform,
           coalesce(nullif(v.value->>'url', ''), v.source_url) url,
           replace(substring(v.value->>'value' from '^\s*([0-9][0-9,]*)'), ',', '')::numeric followers,
           v.retrieved_at, v.created_at
      from vc_source_facts v
     where v.firm_id = p_firm and v.status = 'current' and v.fact_type = 'media_reach'
       and coalesce(v.value->>'entity', '') = 'firm' and v.source_level = 2
       and (v.value->>'field') ~ '^media_[a-z]+_followers$'
  ), good as (
    select * from ok
     where followers is not null and followers >= 0
       and platform in ('linkedin', 'x', 'youtube', 'instagram', 'tiktok', 'substack')
       and url ~* case platform when 'linkedin' then '^https://([a-z0-9-]+\.)?linkedin\.com/'
                                when 'x' then '^https://(www\.|mobile\.)?(x|twitter)\.com/'
                                when 'youtube' then '^https://(www\.|m\.)?youtube\.com/'
                                when 'instagram' then '^https://(www\.)?instagram\.com/'
                                when 'tiktok' then '^https://(www\.)?tiktok\.com/'
                                when 'substack' then '^https://([a-z0-9-]+\.)?substack\.com(/|$)' end
  ), one as (
    select distinct on (platform) platform, url, followers from good
     order by platform, retrieved_at desc nulls last, created_at desc
  )
  select coalesce(jsonb_agg(jsonb_build_object('platform', platform, 'url', url, 'followers', followers)
           order by array_position(array['linkedin', 'x', 'instagram', 'youtube', 'tiktok', 'substack'], platform)), '[]'::jsonb)
    from one
$function$;

delete from public.firm_page_cache;
