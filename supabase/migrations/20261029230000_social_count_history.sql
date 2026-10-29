-- Social counts (Alex 2026-10-29, fix 3): a newer Checker-approved count for the same firm + platform replaces the
-- shown count. The replaced count moves to public.social_count_history (count, date read, source, submission id).
-- A missing or non-numeric count is never published, so the old count stays shown and nothing new appears.
-- Rollback: supabase/rollbacks/20261029230000_social_count_history.sql

create table if not exists public.social_count_history (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  platform text not null,
  url text,
  followers numeric not null,
  read_at date,
  source text,
  source_url text,
  submission_id bigint,
  fact_id uuid not null,
  replaced_by uuid,
  replaced_at timestamptz not null default now()
);
create index if not exists social_count_history_firm on public.social_count_history (firm_id, platform, replaced_at desc);
alter table public.social_count_history enable row level security;
revoke all on table public.social_count_history from public, anon, authenticated;

create or replace function public._checker_social(p_firm uuid, p_f jsonb, p_url text)
returns table(lvl smallint, outcome text, reason text)
language plpgsql security definer set search_path to 'bots', 'public' as $$
declare acct text := public._checker_social_platform(p_f->>'platform'); u text := p_f->>'url';
        rd date; newest date; rid uuid; olds uuid[];
begin
  if coalesce(p_f->>'linked_from_firm_site', '') <> 'true' then
    return query select null::smallint, 'skipped'::text, 'skipped, published via _firm_social'::text; return;
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

CREATE OR REPLACE FUNCTION public.checker_publish_submission(p_id bigint, p_probes jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'bots', 'public'
AS $function$
declare sub bots.research_submissions; fid uuid; it record; lvl smallint; ncheck int; outcome text; reason text;
  pub int := 0; skip int := 0; fail int := 0; unconf int := 0; merged int := 0; noted int := 0; internal int := 0;
  probes jsonb; gate jsonb; host text; claimed text; opened boolean; website boolean;
  reasons jsonb := '[]'::jsonb;
begin
  select * into sub from research_submissions where id = p_id;
  if sub.id is null or not public._checker_publish_on() then
    return jsonb_build_object('ran', false);
  end if;
  -- Step B (A5.5): only rows the entry check Accepted; flagged links are opened first.
  gate := public._checker_entry_gate(sub.id, p_probes);
  if gate is not null then return gate; end if;
  select * into sub from research_submissions where id = p_id;
  select f.id into fid from firms f
   where f.deleted_at is null and f.registry_id = coalesce(public._registry_target(sub.registry_id), sub.registry_id)
   order by f.published desc limit 1;
  if fid is null or not public._lab_firm(fid) then
    return jsonb_build_object('ran', false, 'reason', 'not a lab firm');
  end if;
  probes := coalesce(p_probes, sub.payload->'probes');
  for it in select * from public._checker_payload_items(sub.payload) loop
    begin
      claimed := null;
      website := it.section = 'overview' and lower(coalesce(it.f->>'label', '')) in ('website', 'primary_domain');
      if website then
        host := public._dom(it.url);
        claimed := public._checker_host(it.f->>'value');
        if public.source_tier(it.url) is null then
          lvl := null; outcome := 'failure'; reason := 'link is not real (missing, not http, or a search/chat page)';
        elsif host is null or claimed is null or not (host = claimed or host like '%.' || claimed) then
          lvl := null; outcome := 'failure'; reason := 'link does not match the firm';
        else
          opened := public._checker_link_opens(it.url, probes);
          if opened is null then
            lvl := null; outcome := 'failure'; reason := 'link was not opened';
          elsif not opened then
            lvl := null; outcome := 'failure'; reason := 'link did not open';
          else
            lvl := 2; outcome := 'published'; reason := null;
          end if;
        end if;
      elsif it.section = 'social' then
        ncheck := null;
        select d.lvl, d.outcome, d.reason into lvl, outcome, reason from public._checker_social(fid, it.f || jsonb_build_object('submission_id', p_id), it.url) d;
      else
        ncheck := public._checker_check_n(it.section, it.url);
        select d.lvl, d.outcome, d.reason into lvl, outcome, reason
          from public._checker_decide(fid, it.section, it.f, it.url, ncheck, probes) d;
      end if;
      if outcome = 'published' and it.section <> 'social' then
        select p.outcome, p.reason into outcome, reason
          from public._checker_place(fid, it.section, it.f, it.url, lvl, ncheck, sub.id) p;
      end if;
      if website and outcome in ('published', 'merged', 'skipped') and claimed is not null then
        update firms set primary_domain = claimed
         where id = fid and (primary_domain is null or lower(primary_domain) = claimed);
      end if;
    exception when others then
      outcome := 'failure'; reason := sqlerrm;
    end;
    -- our own write / DB-constraint errors are not the bot's fault: counted apart, never as a failure
    if outcome = 'failure' and public._checker_internal_error(reason) then outcome := 'internal'; end if;
    if outcome = 'published' then pub := pub + 1;
    elsif outcome = 'merged' then merged := merged + 1;
    elsif outcome = 'note' then noted := noted + 1;
    elsif outcome = 'skipped' then skip := skip + 1;
    elsif outcome = 'unconfirmed' then unconf := unconf + 1;
    elsif outcome = 'internal' then internal := internal + 1;
    else fail := fail + 1; end if;
    if outcome is distinct from 'published' and outcome is distinct from 'merged' then
      reasons := reasons || jsonb_build_array(jsonb_build_object('section', it.section, 'url', coalesce(it.f->>'url', it.url),
        'outcome', coalesce(outcome, 'failure'), 'reason', coalesce(reason, 'no reason given')));
    end if;
    if outcome in ('failure', 'unconfirmed', 'internal') then
      insert into checker_holding(firm_id, origin, origin_id, kind, url, outcome, reason, item)
      values (fid, 'submission', sub.id, it.section, it.url,
              case when outcome = 'unconfirmed' then 'unconfirmed' else 'failure' end, reason, it.f);
    end if;
  end loop;
  return jsonb_build_object('ran', true, 'firm_id', fid, 'published', pub, 'merged', merged, 'note', noted,
    'skipped', skip, 'unconfirmed', unconf, 'failure', fail, 'internal', internal, 'reasons', reasons);
end $function$;


delete from public.firm_page_cache;
