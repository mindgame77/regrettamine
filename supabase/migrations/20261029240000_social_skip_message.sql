-- Checker skip message for social accounts the firm's own site does not link to (Alex 2026-10-29).
-- Was 'skipped, published via _firm_social' (untrue since 20261029220000). Only the message changes.
-- Rollback: supabase/rollbacks/20261029240000_social_skip_message.sql

create or replace function public._checker_social(p_firm uuid, p_f jsonb, p_url text)
returns table(lvl smallint, outcome text, reason text)
language plpgsql security definer set search_path to 'bots', 'public' as $$
declare acct text := public._checker_social_platform(p_f->>'platform'); u text := p_f->>'url';
        rd date; newest date; rid uuid; olds uuid[];
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
  rd := coalesce((p_f->>'followers_read_at')::date, current_date);
  select max(v.retrieved_at::date), array_agg(v.id) into newest, olds
    from vc_source_facts v
   where v.firm_id = p_firm and v.status = 'current' and v.fact_type = 'media_reach' and v.source_level = 2
     and coalesce(v.value->>'entity', '') = 'firm' and v.value->>'field' = 'media_' || acct || '_followers';
  if newest is not null and rd <= newest then
    if exists (select 1 from vc_source_facts v where v.id = any(olds)
                 and public._checker_url_key(coalesce(nullif(v.value->>'url', ''), v.source_url)) = public._checker_url_key(u)) then
      return query select 2::smallint, 'skipped'::text, 'already on the page, not re-checked'::text; return;
    end if;
    return query select 2::smallint, 'skipped'::text, 'skipped, the count on the page was read on the same day or later'::text; return;
  end if;
  if olds is not null then
    insert into public.social_count_history(firm_id, platform, url, followers, read_at, source, source_url, submission_id, fact_id)
    select v.firm_id, acct, coalesce(nullif(v.value->>'url', ''), v.source_url),
           replace(substring(v.value->>'value' from '^\s*([0-9][0-9,]*)'), ',', '')::numeric,
           v.retrieved_at::date, coalesce(v.checked_by, v.source_system), v.source_url,
           case when v.value->>'submission_id' ~ '^[0-9]+$' then (v.value->>'submission_id')::bigint end, v.id
      from vc_source_facts v
     where v.id = any(olds) and substring(v.value->>'value' from '^\s*([0-9][0-9,]*)') is not null;
    update vc_source_facts set status = 'superseded',
           external_id = case when external_id is not null then external_id || ':superseded:' || id::text end
     where id = any(olds);
  end if;
  rid := public._checker_write(p_firm, 'social', p_f - 'submission_id', p_url, 2::smallint, null);
  if p_f->>'submission_id' ~ '^[0-9]+$' then
    update vc_source_facts set value = value || jsonb_build_object('submission_id', (p_f->>'submission_id')::bigint) where id = rid;
  end if;
  if olds is not null then
    update vc_source_facts set superseded_by = rid where id = any(olds);
    update public.social_count_history set replaced_by = rid where fact_id = any(olds) and replaced_by is null;
    return query select 2::smallint, 'published'::text, 'replaced an older count (now in social_count_history)'::text; return;
  end if;
  return query select 2::smallint, 'published'::text, null::text;
end $$;

revoke all on function public._checker_social(uuid, jsonb, text) from public, anon, authenticated;
