-- Research gap tracking (staging only; approved by Alex 2026-10-23).
-- research_gaps: one row per unfinished checklist item of a firm, so a gap-fill bot can pick up ONLY those items.
-- Auto: every VALID research_submissions insert (a) opens/refreshes gaps for coverage entries with status blocked/not_searched,
--       (b) resolves open gaps whose checklist_item now has status records/none_found (resolved_by_submission = new id).
-- Coverage entries may carry optional gap_reason (blocked|paywall|login_required|not_found_source|not_searched|time_cap|out_of_scope)
-- and tried_routes (text or array). Default reason: blocked -> 'blocked', not_searched -> 'not_searched'.
-- Rollback: drop trigger research_gaps_from_submission on research_submissions; drop function research_gaps_sync(),
--   research_gaps_list(text,int), research_claim_gaps(text,text), research_gaps_release_stale(); drop table research_gaps.
create table if not exists public.research_gaps (
  id bigserial primary key,
  registry_id text not null references public.research_queue(registry_id) on delete cascade,
  check_id text not null,
  reason text not null check (reason in ('blocked','paywall','login_required','not_found_source','not_searched','time_cap','out_of_scope')),
  tried_routes text,
  detail text,
  status text not null default 'open' check (status in ('open','claimed','resolved')),
  claimed_by text, claimed_at timestamptz,
  source_submission bigint references public.research_submissions(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by_submission bigint references public.research_submissions(id) on delete set null);
create unique index if not exists research_gaps_one_unresolved on public.research_gaps(registry_id, check_id) where status <> 'resolved';
create index if not exists research_gaps_open on public.research_gaps(status, registry_id);
alter table public.research_gaps enable row level security;   -- no policies: service_role only
revoke all on public.research_gaps from anon, authenticated;

create or replace function public.research_gaps_sync() returns trigger
language plpgsql security definer set search_path = public as $$
declare c jsonb; st text; ci text; rs text; tr text;
begin
  if not new.valid or jsonb_typeof(new.payload->'coverage') is distinct from 'array' then return new; end if;
  for c in select * from jsonb_array_elements(new.payload->'coverage') loop
    ci := left(nullif(trim(c->>'checklist_item'),''),200); st := c->>'status';
    continue when ci is null;
    if st in ('records','none_found') then
      update research_gaps set status='resolved', resolved_at=now(), resolved_by_submission=new.id, updated_at=now(),
             claimed_by=null, claimed_at=null
       where registry_id=new.registry_id and check_id=ci and status<>'resolved';
    elsif st in ('blocked','not_searched') then
      rs := coalesce(nullif(c->>'gap_reason',''), case st when 'blocked' then 'blocked' else 'not_searched' end);
      if rs not in ('blocked','paywall','login_required','not_found_source','not_searched','time_cap','out_of_scope') then rs := st; end if;
      tr := case jsonb_typeof(c->'tried_routes') when 'array' then (select string_agg(x,'; ') from jsonb_array_elements_text(c->'tried_routes') x)
                 else c->>'tried_routes' end;
      insert into research_gaps (registry_id, check_id, reason, tried_routes, detail, source_submission)
        values (new.registry_id, ci, rs, left(tr,4000), left(c->>'note',4000), new.id)
      on conflict (registry_id, check_id) where status <> 'resolved' do update
        set reason=excluded.reason, tried_routes=excluded.tried_routes, detail=excluded.detail,
            source_submission=excluded.source_submission, status='open', claimed_by=null, claimed_at=null, updated_at=now();
    end if;
  end loop;
  return new;
end $$;
drop trigger if exists research_gaps_from_submission on public.research_submissions;
create trigger research_gaps_from_submission after insert on public.research_submissions
  for each row execute function public.research_gaps_sync();

-- list open (and stale-claimed) gaps, optionally for one firm
create or replace function public.research_gaps_list(p_registry text, p_limit int) returns jsonb
language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(g) - 'source_submission' order by g.registry_id, g.id), '[]'::jsonb) from (
    select id, registry_id, check_id, reason, tried_routes, detail, status, claimed_by, created_at, source_submission
      from research_gaps
     where (status='open' or (status='claimed' and claimed_at < now() - interval '2 hours'))
       and (p_registry is null or registry_id = p_registry)
     order by registry_id, id limit greatest(1, least(coalesce(p_limit,100),500))) g $$;

-- claim ALL open gaps of one firm (oldest firm first, or p_registry). Also puts the firm's queue row in 'claimed' by this bot
-- (allowed only from submitted/claimed-by-same-bot) so the bot can resubmit one merged, complete dump.
create or replace function public.research_claim_gaps(p_bot text, p_registry text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare rid text; q research_queue; gs jsonb;
begin
  if coalesce(p_bot,'') = '' then return jsonb_build_object('ok',false,'error','bot_id required'); end if;
  update research_gaps set status='open', claimed_by=null, claimed_at=null, updated_at=now()
   where status='claimed' and claimed_at < now() - interval '2 hours';
  select g.registry_id into rid from research_gaps g join research_queue rq using (registry_id)
   where g.status='open' and (p_registry is null or g.registry_id=p_registry)
     and (rq.status='submitted' or (rq.status='claimed' and rq.claimed_by=p_bot))
   order by g.created_at, g.id limit 1 for update of rq skip locked;
  if rid is null then return jsonb_build_object('ok',true,'gaps','[]'::jsonb,'none_left',true); end if;
  update research_queue set status='claimed', claimed_by=p_bot, claimed_at=now(), updated_at=now(),
         last_error='gap-fill claim' where registry_id=rid returning * into q;
  with u as (update research_gaps set status='claimed', claimed_by=p_bot, claimed_at=now(), updated_at=now()
              where registry_id=rid and status='open' returning id, check_id, reason, tried_routes, detail)
  select jsonb_agg(to_jsonb(u) order by id) into gs from u;
  return jsonb_build_object('ok',true,'registry_id',rid,'name',q.name,'latest_valid_submission',
    (select max(id) from research_submissions where registry_id=rid and valid),'gaps',gs,'none_left',false);
end $$;

do $$ declare f text; begin
  foreach f in array array['research_gaps_sync()','research_gaps_list(text,int)','research_claim_gaps(text,text)'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
    execute format('grant execute on function public.%s to service_role', f);
  end loop; end $$;

-- backfill from the latest valid submission per firm
insert into public.research_gaps (registry_id, check_id, reason, tried_routes, detail, source_submission)
select s.registry_id, left(c->>'checklist_item',200),
       case when c->>'gap_reason' in ('blocked','paywall','login_required','not_found_source','not_searched','time_cap','out_of_scope') then c->>'gap_reason'
            when c->>'status'='blocked' then 'blocked' else 'not_searched' end,
       c->>'tried_routes', left(c->>'note',4000), s.id
  from (select distinct on (registry_id) * from public.research_submissions where valid order by registry_id, id desc) s,
       jsonb_array_elements(case when jsonb_typeof(s.payload->'coverage')='array' then s.payload->'coverage' else '[]'::jsonb end) c
 where c->>'status' in ('blocked','not_searched') and coalesce(c->>'checklist_item','') <> ''
on conflict do nothing;
