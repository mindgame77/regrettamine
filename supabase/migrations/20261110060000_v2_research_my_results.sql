-- Read-only "my results" for research bots on the v2 door (action results).
-- Copies the old research_my_results pattern: bot from bots.ingest_keys of the
-- authenticated key (active, linked bot_id), never from the request body; last
-- 30 days. Rejected and held items in that window are always returned (up to 500).
-- p_limit (default 100, max 200) caps only the live items.
-- It reads only v2 tables (submissions, checker queue/verdicts, firm boxes). It does not read the old v1 submission table or other v1 data, and
-- it does not write, publish, or change any row.
-- A bot sees only rows whose v2_research_submissions.bot_key_id matches
-- v2_bot_keys.bot_name = ingest_keys.bot_id. Optional firm_id filter.
-- Checker reason text comes from v2_checker_verdicts.reason, word for word.
-- Rollback: supabase/rollbacks/20261110060000_v2_research_my_results.sql
-- The v2 schema is not created by repo migrations. On a database without v2
-- (CI) this is a no-op.

do $mig$
begin
  if to_regclass('public.v2_firms') is null
     or to_regclass('public.v2_bot_keys') is null
     or to_regclass('public.v2_research_submissions') is null
     or to_regclass('public.v2_checker_queue') is null
     or to_regclass('public.v2_checker_verdicts') is null
     or to_regclass('public.v2_deals') is null
     or to_regclass('public.v2_startups') is null
     or to_regclass('public.v2_startup_sectors') is null
     or to_regclass('public.v2_funds') is null
     or to_regclass('public.v2_social_accounts') is null
     or to_regclass('public.v2_person_firm_roles') is null
     or to_regclass('public.v2_investor_principles') is null
     or to_regclass('bots.ingest_keys') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;

  execute $ddl$
create or replace function public.v2_research_my_results(
  p_key uuid, p_days int default 30, p_limit int default 100, p_firm_id bigint default null)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path = public, bots
 as $function$
declare
  v_bot text;
  d int := least(greatest(coalesce(p_days, 30), 1), 30);
  n int := least(greatest(coalesce(p_limit, 100), 1), 200);
  v_key_id bigint;
begin
  select k.bot_id into v_bot from bots.ingest_keys k where k.id = p_key and k.active;
  if nullif(btrim(v_bot), '') is null then
    return jsonb_build_object('ok', false, 'error', 'this key is not linked to a bot; ask Alex to link it');
  end if;

  select bk.bot_key_id into v_key_id from public.v2_bot_keys bk where bk.bot_name = v_bot;
  if v_key_id is null then
    return jsonb_build_object(
      'ok', true, 'bot_id', v_bot, 'days', d,
      'counts', jsonb_build_object('live', 0, 'held', 0, 'rejected', 0),
      'items', '[]'::jsonb, 'firms', '[]'::jsonb);
  end if;

  return jsonb_build_object(
    'ok', true,
    'bot_id', v_bot,
    'days', d,
    'counts', (
      select jsonb_build_object(
        'live', count(*) filter (where i.status = 'live'),
        'held', count(*) filter (where i.status = 'held'),
        'rejected', count(*) filter (where i.status = 'rejected'))
      from public._v2_research_my_result_items(v_key_id, d, p_firm_id) i
    ),
    'items', coalesce((
      select jsonb_agg(to_jsonb(s) - 'sort_status' - 'rn' - 'bucket'
                       order by s.sort_status, s.received_at desc, s.submission_id desc)
      from (
        select *
        from (
          select i.*,
                 case when i.status in ('rejected', 'held') then 'need' else 'live' end as bucket,
                 row_number() over (
                   partition by case when i.status in ('rejected', 'held') then 'need' else 'live' end
                   order by i.sort_status, i.received_at desc, i.submission_id desc
                 ) as rn
            from public._v2_research_my_result_items(v_key_id, d, p_firm_id) i
        ) z
        where (z.bucket = 'need' and z.rn <= 500)
           or (z.bucket = 'live' and z.rn <= n)
      ) s
    ), '[]'::jsonb),
    'firms', coalesce((
      select jsonb_agg(jsonb_build_object(
               'firm_id', f.firm_id,
               'name', f.display_name,
               'slug', f.slug,
               'not_sent', public._v2_research_not_sent(f.firm_id))
             order by f.display_name, f.firm_id)
      from public.v2_firms f
      where f.firm_id in (
        select distinct s.firm_id
          from public.v2_research_submissions s
         where s.bot_key_id = v_key_id
           and s.received_at > now() - make_interval(days => d)
           and s.firm_id is not null
           and (p_firm_id is null or s.firm_id = p_firm_id)
      )
    ), '[]'::jsonb)
  );
end
$function$;
$ddl$;

  execute $ddl$
create or replace function public._v2_research_my_result_items(
  p_bot_key_id bigint, p_days int, p_firm_id bigint)
 returns table (
   submission_id bigint,
   queue_id bigint,
   firm_id bigint,
   firm text,
   slug text,
   box text,
   "table" text,
   kind text,
   label text,
   status text,
   reason text,
   received_at timestamptz,
   decided_at timestamptz,
   sort_status int
 )
 language sql
 stable
 security definer
 set search_path = public, bots
 as $function$
  select
    s.submission_id,
    q.queue_id,
    s.firm_id,
    f.display_name::text,
    f.slug::text,
    s.target_box,
    q.table_name,
    q.kind,
    nullif(coalesce(
      nullif(btrim(q.new_value->>'startup_name'), ''),
      nullif(btrim(q.new_value->>'person_name'), ''),
      nullif(btrim(q.new_value->>'fund_name'), ''),
      nullif(btrim(q.new_value->>'display_name'), ''),
      nullif(btrim(q.new_value->>'legal_name'), ''),
      nullif(btrim(q.new_value->>'industry_text'), ''),
      nullif(btrim(q.new_value->>'stage'), ''),
      nullif(btrim(q.new_value->>'platform'), ''),
      nullif(left(btrim(q.new_value->>'quote'), 80), ''),
      nullif(left(btrim(q.new_value->>'headline'), 80), ''),
      nullif(btrim(q.new_value->>'round'), ''),
      nullif(btrim(s.payload#>>'{fact,startup_name}'), ''),
      nullif(btrim(s.payload#>>'{fact,person_name}'), ''),
      nullif(btrim(s.payload#>>'{fact,fund_name}'), ''),
      nullif(left(btrim(s.payload#>>'{fact,quote}'), 80), '')
    ), '') as label,
    x.status,
    case
      when nullif(btrim(v.reason), '') is not null then v.reason
      when s.status like 'Rejected: Checker: %' then substr(s.status, 20)
      when s.status like 'Rejected: %' then substr(s.status, 11)
      when s.status like 'Held: %' then substr(s.status, 7)
      else null
    end as reason,
    s.received_at,
    v.created_at as decided_at,
    case x.status when 'rejected' then 1 when 'held' then 2 else 3 end as sort_status
  from public.v2_research_submissions s
  left join public.v2_firms f on f.firm_id = s.firm_id
  left join public.v2_checker_queue q on q.submission_id = s.submission_id
  left join lateral (
    select vv.reason, vv.verdict, vv.created_at
      from public.v2_checker_verdicts vv
     where vv.queue_id = q.queue_id
     order by vv.created_at desc, vv.verdict_id desc
     limit 1
  ) v on true
  cross join lateral (
    select case
      when v.verdict = 'reject' or q.status = 'failed' or s.status like 'Rejected%' then 'rejected'
      when q.status in ('open', 'held-for-alex') or s.status like 'Held%' then 'held'
      else 'live'
    end as status
  ) x
  where s.bot_key_id = p_bot_key_id
    and s.received_at > now() - make_interval(days => p_days)
    and (p_firm_id is null or s.firm_id = p_firm_id);
$function$;
$ddl$;

  execute $ddl$
create or replace function public._v2_research_not_sent(p_firm_id bigint)
 returns jsonb
 language sql
 stable
 security definer
 set search_path = public
 as $function$
  select coalesce(jsonb_agg(x order by ord), '[]'::jsonb)
  from (
    select 1 as ord, 'HQ is empty, look for it.' as x
      from public.v2_firms f
     where f.firm_id = p_firm_id
       and f.hq_street is null and f.hq_suite is null and f.hq_city is null
       and f.hq_state is null and f.hq_postal is null and f.hq_country is null
    union all
    select 2, 'Founded year is empty, look for it.'
      from public.v2_firms f
     where f.firm_id = p_firm_id and f.founded_year is null
    union all
    select 3, 'Thesis is empty, look for it.'
      from public.v2_firms f
     where f.firm_id = p_firm_id and nullif(btrim(f.thesis_text), '') is null
    union all
    select 4, 'Team was not sent, look for it.'
     where not exists (
       select 1 from public.v2_person_firm_roles r
        where r.firm_id = p_firm_id
          and not coalesce(r.archived, false)
          and coalesce(r.is_current, true)
     )
    union all
    select 5, 'Quotes were not sent, look for it.'
     where not exists (
       select 1 from public.v2_investor_principles p
        where p.firm_id = p_firm_id
          and not coalesce(p.archived, false)
          and coalesce(p.is_current, true)
     )
    union all
    select 6, 'Funds were not sent, look for it.'
     where not exists (
       select 1 from public.v2_funds fu
        where fu.firm_id = p_firm_id and not coalesce(fu.archived, false)
     )
    union all
    select 7, 'Socials were not sent, look for it.'
     where not exists (
       select 1 from public.v2_social_accounts sa
        where sa.firm_id = p_firm_id
          and not coalesce(sa.archived, false)
          and coalesce(sa.is_current, true)
     )
    union all
    select 8, format('%s startups have no sector, look for it.', n)
      from (
        select count(distinct s.startup_id)::int as n
          from public.v2_deals d
          join public.v2_startups s on s.startup_id = d.startup_id
         where d.firm_id = p_firm_id
           and not coalesce(d.archived, false)
           and not coalesce(s.archived, false)
           and not exists (
             select 1 from public.v2_startup_sectors ss
              where ss.startup_id = s.startup_id and not coalesce(ss.archived, false)
           )
      ) t
     where t.n > 0
    union all
    select 9, format('%s deals have no exact date, look for it.', n)
      from (
        select count(*)::int as n
          from public.v2_deals d
         where d.firm_id = p_firm_id
           and not coalesce(d.archived, false)
           and (d.deal_date is null or d.deal_date_precision is distinct from 'full date')
      ) t
     where t.n > 0
  ) z;
$function$;
$ddl$;

  -- Helpers are internal. Only the door-facing function is granted to service_role.
  execute 'revoke all on function public.v2_research_my_results(uuid, int, int, bigint) from public, anon, authenticated';
  execute 'revoke all on function public._v2_research_my_result_items(bigint, int, bigint) from public, anon, authenticated';
  execute 'revoke all on function public._v2_research_not_sent(bigint) from public, anon, authenticated';
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.v2_research_my_results(uuid, int, int, bigint) to service_role';
  end if;
end
$mig$;
