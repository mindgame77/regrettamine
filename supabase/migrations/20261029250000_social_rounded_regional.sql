-- socialAccounts markers (rulebook A15.6 / A15.7, Alex 2026-10-29):
--   rounded:boolean   the platform only shows a rounded count (YouTube "20.1K"). Shown like any count; an exact count
--                     for the same account replaces it (old row -> social_count_history). A rounded count never
--                     replaces an exact one.
--   regional:boolean + region:text   a firm's regional account (LightspeedIndia), linked from the firm's own site.
--                     Its own pill per (platform, region); it never replaces, and is never replaced by, the main account.
-- The markers are stored on the approved fact (vc_source_facts.value) and in social_count_history.
-- Rollback: supabase/rollbacks/20261029250000_social_rounded_regional.sql

alter table public.social_count_history add column if not exists rounded boolean;
alter table public.social_count_history add column if not exists region text;

create or replace function public._checker_social(p_firm uuid, p_f jsonb, p_url text)
returns table(lvl smallint, outcome text, reason text)
language plpgsql security definer set search_path to 'bots', 'public' as $$
declare acct text := public._checker_social_platform(p_f->>'platform'); u text := p_f->>'url';
        rd date; newest date; rid uuid; olds uuid[];
        is_rounded boolean := coalesce(p_f->>'rounded', '') = 'true';
        is_regional boolean := coalesce(p_f->>'regional', '') = 'true';
        reg text := nullif(btrim(coalesce(p_f->>'region', '')), '');
        rkey text; marks jsonb; exact_old boolean; rounded_old boolean;
begin
  if coalesce(p_f->>'linked_from_firm_site', '') <> 'true' then
    return query select null::smallint, 'skipped'::text, 'skipped: not linked from the firm''s site, not shown'::text; return;
  end if;
  if acct is null or acct not in ('linkedin', 'x', 'youtube', 'instagram', 'tiktok', 'substack') then
    return query select null::smallint, 'skipped'::text, ('skipped, platform ' || coalesce(acct, 'missing') || ' is not shown on the page')::text; return;
  end if;
  if u is null or u !~* '^https?://[^\s/]+\.[^\s]+$' then
    return query select null::smallint, 'failure'::text, 'social account needs url'::text; return;
  end if;
  if jsonb_typeof(p_f->'followers') is distinct from 'number' then
    return query select null::smallint, 'failure'::text, 'social followers must be a number'::text; return;
  end if;
  if (p_f ? 'rounded' and jsonb_typeof(p_f->'rounded') <> 'boolean') or (p_f ? 'regional' and jsonb_typeof(p_f->'regional') <> 'boolean') then
    return query select null::smallint, 'failure'::text, 'social rounded and regional must be true or false'::text; return;
  end if;
  if is_regional and (reg is null or length(reg) > 40) then
    return query select null::smallint, 'failure'::text, 'regional social account needs a region'::text; return;
  end if;
  if not is_regional then reg := null; end if;
  rkey := lower(coalesce(reg, ''));
  marks := jsonb_strip_nulls(jsonb_build_object('rounded', case when is_rounded then true end,
                                                'regional', case when is_regional then true end, 'region', reg));
  rd := coalesce((p_f->>'followers_read_at')::date, current_date);
  select max(v.retrieved_at::date), array_agg(v.id),
         bool_or(coalesce(v.value->>'rounded', '') <> 'true'), bool_or(coalesce(v.value->>'rounded', '') = 'true')
    into newest, olds, exact_old, rounded_old
    from vc_source_facts v
   where v.firm_id = p_firm and v.status = 'current' and v.fact_type = 'media_reach' and v.source_level = 2
     and coalesce(v.value->>'entity', '') = 'firm' and v.value->>'field' = 'media_' || acct || '_followers'
     and lower(coalesce(case when v.value->>'regional' = 'true' then v.value->>'region' end, '')) = rkey;
  if newest is not null and is_rounded and exact_old then
    return query select 2::smallint, 'skipped'::text, 'skipped, the page already has an exact count'::text; return;
  end if;
  -- an exact count replaces a rounded one read the same day (A15.6); otherwise only a newer read replaces
  if newest is not null and (rd < newest or (rd = newest and not (not is_rounded and rounded_old and not exact_old))) then
    if exists (select 1 from vc_source_facts v where v.id = any(olds)
                 and public._checker_url_key(coalesce(nullif(v.value->>'url', ''), v.source_url)) = public._checker_url_key(u)) then
      return query select 2::smallint, 'skipped'::text, 'already on the page, not re-checked'::text; return;
    end if;
    return query select 2::smallint, 'skipped'::text, 'skipped, the count on the page was read on the same day or later'::text; return;
  end if;
  if olds is not null then
    insert into public.social_count_history(firm_id, platform, url, followers, read_at, source, source_url, submission_id, fact_id, rounded, region)
    select v.firm_id, acct, coalesce(nullif(v.value->>'url', ''), v.source_url),
           replace(substring(v.value->>'value' from '^\s*([0-9][0-9,]*)'), ',', '')::numeric,
           v.retrieved_at::date, coalesce(v.checked_by, v.source_system), v.source_url,
           case when v.value->>'submission_id' ~ '^[0-9]+$' then (v.value->>'submission_id')::bigint end, v.id,
           v.value->>'rounded' = 'true', case when v.value->>'regional' = 'true' then v.value->>'region' end
      from vc_source_facts v
     where v.id = any(olds) and substring(v.value->>'value' from '^\s*([0-9][0-9,]*)') is not null;
    update vc_source_facts set status = 'superseded',
           external_id = case when external_id is not null then external_id || ':superseded:' || id::text end
     where id = any(olds);
  end if;
  rid := public._checker_write(p_firm, 'social', p_f - 'submission_id' - 'rounded' - 'regional' - 'region', p_url, 2::smallint, null);
  update vc_source_facts set value = value || marks
      || case when p_f->>'submission_id' ~ '^[0-9]+$' then jsonb_build_object('submission_id', (p_f->>'submission_id')::bigint) else '{}'::jsonb end
   where id = rid;
  if olds is not null then
    update vc_source_facts set superseded_by = rid where id = any(olds);
    update public.social_count_history set replaced_by = rid where fact_id = any(olds) and replaced_by is null;
    return query select 2::smallint, 'published'::text, 'replaced an older count (now in social_count_history)'::text; return;
  end if;
  return query select 2::smallint, 'published'::text, null::text;
end $$;

revoke all on function public._checker_social(uuid, jsonb, text) from public, anon, authenticated;

-- One pill per (platform, region). Main accounts first, output unchanged for them; a regional pill adds "region".
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
           case when v.value->>'regional' = 'true' then nullif(btrim(v.value->>'region'), '') end region,
           v.retrieved_at, v.created_at
      from vc_source_facts v
     where v.firm_id = p_firm and v.status = 'current' and v.fact_type = 'media_reach'
       and coalesce(v.value->>'entity', '') = 'firm' and v.source_level = 2
       and (v.value->>'field') ~ '^media_[a-z]+_followers$'
       and (coalesce(v.value->>'regional', '') <> 'true' or nullif(btrim(v.value->>'region'), '') is not null)
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
    select distinct on (platform, lower(coalesce(region, ''))) platform, url, followers, region from good
     order by platform, lower(coalesce(region, '')), retrieved_at desc nulls last, created_at desc
  )
  select coalesce(jsonb_agg(jsonb_build_object('platform', platform, 'url', url, 'followers', followers)
             || case when region is not null then jsonb_build_object('region', region) else '{}'::jsonb end
           order by region is not null, lower(coalesce(region, '')),
                    array_position(array['linkedin', 'x', 'instagram', 'youtube', 'tiktok', 'substack'], platform)), '[]'::jsonb)
    from one
$function$;

delete from public.firm_page_cache;
