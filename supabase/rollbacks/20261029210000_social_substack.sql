-- Rollback for 20261029210000_social_substack.sql: _firm_social and _checker_social without substack.

CREATE OR REPLACE FUNCTION public._firm_social(p_firm uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with raw as (
    select lower(coalesce(r->'value'->>'platform', '')) platform, r->'value'->>'url' url,
           case when jsonb_typeof(r->'value'->'followers') = 'number' then (r->'value'->>'followers')::numeric end followers,
           s.received_at retrieved_at, s.received_at created_at
      from firms f
      join bots.research_submissions s on s.registry_id = coalesce(f.registry_id, public._firm_queue_id(f.id)) and s.valid
      cross join lateral jsonb_array_elements(coalesce(s.payload->'records', '[]'::jsonb)) r
     where f.id = p_firm and r->>'field_path' = 'socialAccounts'
       and jsonb_typeof(r->'value') = 'object' and (r->'value'->>'linked_from_firm_site') = 'true'
    union all
    select substring(v.value->>'field' from '^media_([a-z]+)_followers$'),
           coalesce(nullif(v.value->>'url', ''), v.source_url),
           replace(substring(v.value->>'value' from '^\s*([0-9][0-9,]*)'), ',', '')::numeric,
           v.retrieved_at, v.created_at
      from vc_source_facts v
     where v.firm_id = p_firm and v.status = 'current' and v.fact_type = 'media_reach'
       and coalesce(v.value->>'entity', '') = 'firm' and v.source_level = 2
       and (v.value->>'field') ~ '^media_[a-z]+_followers$'
  ), ok as (
    select case platform when 'twitter' then 'x' else platform end platform, url, followers, retrieved_at, created_at from raw
     where followers is not null and followers >= 0
  ), good as (
    select * from ok
     where platform in ('linkedin', 'x', 'youtube', 'instagram', 'tiktok')
       and url ~* case platform when 'linkedin' then '^https://([a-z0-9-]+\.)?linkedin\.com/'
                                when 'x' then '^https://(www\.|mobile\.)?(x|twitter)\.com/'
                                when 'youtube' then '^https://(www\.|m\.)?youtube\.com/'
                                when 'instagram' then '^https://(www\.)?instagram\.com/'
                                when 'tiktok' then '^https://(www\.)?tiktok\.com/' end
  ), one as (
    select distinct on (platform) platform, url, followers from good
     order by platform, retrieved_at desc nulls last, created_at desc
  )
  select coalesce(jsonb_agg(jsonb_build_object('platform', platform, 'url', url, 'followers', followers)
           order by array_position(array['linkedin', 'x', 'instagram', 'youtube', 'tiktok'], platform)), '[]'::jsonb)
    from one
$function$;

create or replace function public._checker_social(p_firm uuid, p_f jsonb, p_url text)
returns table(lvl smallint, outcome text, reason text)
language plpgsql security definer set search_path to 'bots', 'public' as $$
declare acct text := public._checker_social_platform(p_f->>'platform'); u text := p_f->>'url';
begin
  if coalesce(p_f->>'linked_from_firm_site', '') <> 'true' then
    return query select null::smallint, 'skipped'::text, 'skipped, published via _firm_social'::text; return;
  end if;
  if acct is null or acct not in ('linkedin', 'x', 'youtube', 'instagram', 'tiktok') then
    return query select null::smallint, 'skipped'::text, ('skipped, platform ' || coalesce(acct, 'missing') || ' is not shown on the page')::text; return;
  end if;
  if u is null or u !~* '^https?://[^\s/]+\.[^\s]+$' then
    return query select null::smallint, 'failure'::text, 'social account needs url'::text; return;
  end if;
  if jsonb_typeof(p_f->'followers') is distinct from 'number' then
    return query select null::smallint, 'failure'::text, 'social followers must be a number'::text; return;
  end if;
  if exists (select 1 from vc_source_facts v where v.firm_id = p_firm and v.status = 'current' and v.fact_type = 'media_reach'
               and v.source_level = 2 and v.value->>'field' = 'media_' || acct || '_followers'
               and public._checker_url_key(coalesce(nullif(v.value->>'url', ''), v.source_url)) = public._checker_url_key(u)) then
    return query select 2::smallint, 'skipped'::text, 'already on the page, not re-checked'::text; return;
  end if;
  perform public._checker_write(p_firm, 'social', p_f, p_url, 2::smallint, null);
  return query select 2::smallint, 'published'::text, null::text;
end $$;

revoke all on function public._checker_social(uuid, jsonb, text) from public, anon, authenticated;

delete from public.firm_page_cache;
