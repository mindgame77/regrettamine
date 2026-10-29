-- Social pills in the firm header (Alex 2026-10-29, approved mockup 02-social-v2a-pills; PAGE_DATA_GUIDE A2.10, B3.8).
-- firm_page().firm gets 'social': one entry per platform {platform, url, followers}, only for an account linked from the
-- firm's own website (level 2). Stored rows read, nothing written:
--   socialAccounts records in valid research-ingest submissions (bots.research_submissions, linked_from_firm_site = true), or
--   vc_source_facts media_reach rows for the firm itself (entity 'firm', field media_<platform>_followers) with source_level 2.
-- A count from anywhere else is Unconfirmed and not returned. No row: [] (the page hides the whole row).
-- Rollback: supabase/rollbacks/20261029120000_firm_social_pills.sql

create or replace function public._firm_social(p_firm uuid)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
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
revoke all on function public._firm_social(uuid) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.firm_page(p_slug text, p_anon uuid, p_spend boolean DEFAULT false, p_email text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare f firms; u json; open boolean; secs jsonb := '[]'; s page_sections; it jsonb; hero jsonb; q research_queue; qid text;
  vq text; vs timestamptz; hq text; web text; assets text;
begin
  select * into f from firms where slug = p_slug and deleted_at is null and published and not coalesce(is_test, false) and data_status = 'real';
  if f.id is null then return json_build_object('status', 'not_found'); end if;
  u := unlock_firm(p_slug, p_anon, p_spend, p_email);
  open := u->>'status' = 'ok';
  if u->>'status' not in ('ok', 'locked') then return u; end if;
  qid := _firm_queue_id(f.id);
  if qid is not null then select * into q from research_queue where registry_id = qid; end if;
  hq := coalesce(nullif(btrim(f.hq), ''), public.firm_hq_format(q.hq_city, q.state, q.country));
  web := public._firm_website(f.id, f.primary_domain);
  assets := public._firm_assets(f.id);
  if not open then
    select coalesce(jsonb_agg(jsonb_build_object('label', hero_label, 'value', hero_value, 'anchor', section, 'src', _src('firm_profile_facts', id)) order by section desc, sort_order), '[]') into hero
      from firm_profile_facts where firm_id = f.id and not hidden and hero_label is not null and exists (select 1 from fact_sources where fact_type = 'firm_profile_facts' and fact_id = firm_profile_facts.id);
    vq := case when public._visitor_checking(q) then 'claimed' when q.status = 'claimed' then 'queued' else q.status end;
    vs := case when public._visitor_checking(q) then q.claimed_at end;
    if not f.indexable and jsonb_array_length(hero) = 0 then
      select coalesce(jsonb_agg(jsonb_build_object('label', l, 'value', v, 'anchor', 'overview', 'src', '[]'::jsonb) order by o), '[]') into hero
        from (values (1, 'HQ', hq), (2, 'SEC CRD', nullif(q.sec_crd, '')), (3, 'LEI', nullif(q.lei, ''))) x(o, l, v) where v is not null;
    end if;
    return json_build_object('status', 'ok', 'open', false, 'locked', u->>'status', 'unchecked', not f.indexable,
      'firm', json_build_object('slug', f.slug, 'name', coalesce(f.display_name, f.name), 'sec_name', coalesce(f.legal_name, f.name), 'short_name', f.short_name, 'hq', hq, 'website', web, 'assets', assets, 'social', public._firm_social(f.id)),
      'hero', hero, 'sections', '[]'::json, 'done', _firm_checks_done(f.id),
      'checks', (select json_agg(json_build_object('n', e->'n', 'title', e->'title', 'descr', e->'descr', 'state', null, 'count', null, 'searched_at', null, 'items', null, 'itemized', null, 'name_only', null)) from json_array_elements(public._check_placeholders()) e),
      'queue', vq, 'started_at', vs, 'details', null, 'outline', null, 'ondemand', _ondemand_view(f.id, p_anon), 'activity', public._firm_activity(f.id, open));
  end if;
  for s in select * from page_sections where enabled order by sort_order loop
    it := _sec_items(s.key, f.id);
    continue when jsonb_array_length(it) = 0;
    secs := secs || jsonb_build_object('key', s.key, 'title', s.title, 'subtitle', s.subtitle, 'renderer', s.renderer,
      'count', jsonb_array_length(it), 'unit', case when jsonb_array_length(it) = 1 then s.unit_one else s.unit_many end,
      'teaser', it->0->>'head', 'items', it);
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('label', hero_label, 'value', hero_value, 'anchor', section, 'src', _src('firm_profile_facts', id)) order by section desc, sort_order), '[]') into hero
    from firm_profile_facts where firm_id = f.id and not hidden and hero_label is not null and exists (select 1 from fact_sources where fact_type = 'firm_profile_facts' and fact_id = firm_profile_facts.id);
  vq := case when public._visitor_checking(q) then 'claimed' when q.status = 'claimed' then 'queued' else q.status end;
  vs := case when public._visitor_checking(q) then q.claimed_at end;
  return json_build_object('status', 'ok', 'open', true, 'unchecked', false, 'done', _firm_checks_done(f.id),
    'firm', json_build_object('slug', f.slug, 'name', coalesce(f.display_name, f.name), 'sec_name', coalesce(f.legal_name, f.name), 'short_name', f.short_name, 'hq', hq, 'website', web, 'assets', assets, 'social', public._firm_social(f.id)),
    'hero', hero, 'sections', secs,
    'checks', public._firm_checks(f.id),
    'queue', vq, 'started_at', vs, 'details', u->'details', 'outline', null, 'ondemand', _ondemand_view(f.id, p_anon), 'activity', public._firm_activity(f.id, open));
end $function$;

-- cached pages do not carry the new field yet
delete from public.firm_page_cache;
