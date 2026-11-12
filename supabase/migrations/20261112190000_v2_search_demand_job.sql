-- B. Search demand behavior.
-- Claim order, hide-until-researched, the 6-hour matcher, and the go-live email.
-- Runs only after 20261112180000 (the tables and demand_hidden). Does not rewrite existing rows.
-- CI has no v2 schema: this is a no-op there.
-- Email uses the existing ondemand-notify worker (Resend). Deploy that function before applying this file,
-- so kind search_live is not sent with the "we got your request" wording.
-- Undo: supabase/rollbacks/20261112190000_v2_search_demand_job.sql
do $mig$
begin
  if to_regclass('public.v2_firms') is null
     or to_regclass('public.v2_firm_live') is null
     or to_regclass('public.v2_research_assignments') is null
     or to_regclass('public.v2_search_log') is null
     or to_regclass('public.v2_firm_watch') is null
     or to_regclass('public.research_queue') is null
     or to_regprocedure('public.v2_search_norm(text)') is null
     or to_regprocedure('public.v2_research_claim(uuid)') is null then
    raise notice 'v2 search demand job skipped';
    return;
  end if;
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'v2_firms' and column_name = 'demand_hidden'
  ) then
    raise notice 'demand_hidden missing, v2 search demand job skipped';
    return;
  end if;

  execute 'alter table public.v2_research_assignments add column if not exists priority text not null default ''normal''';
  if not exists (
    select 1 from pg_constraint where conname = 'v2_research_assignments_priority_ck'
  ) then
    execute $ck$
      alter table public.v2_research_assignments
        add constraint v2_research_assignments_priority_ck check (priority in ('top', 'normal'))
    $ck$;
  end if;
  execute $pc$
    comment on column public.v2_research_assignments.priority is
      'top is claimed before normal. Same firm_id order inside a priority. Default normal.'
  $pc$;
  execute $pix$
    create index if not exists v2_research_assignments_priority_open
      on public.v2_research_assignments ((case when priority = 'top' then 0 else 1 end), firm_id)
      where done_at is null
  $pix$;

  -- Same function as 20261108165320. The only change is the ORDER BY.
  execute $claim$
CREATE OR REPLACE FUNCTION public.v2_research_claim(p_key_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'bots'
 SET statement_timeout TO '30s'
 SET lock_timeout TO '5s'
AS $function$
DECLARE
  ik bots.ingest_keys;
  bk public.v2_bot_keys;
  bot text;
  fid bigint;
  frm public.v2_firms;
BEGIN
  SELECT * INTO ik FROM bots.ingest_keys WHERE id = p_key_id AND active;
  IF NOT FOUND OR ik.bot_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'this key is not linked to a bot');
  END IF;
  bot := ik.bot_id;
  INSERT INTO public.v2_bot_keys (bot_name, key_hash) VALUES (bot, ik.key_hash)
    ON CONFLICT (bot_name) DO UPDATE SET key_hash = EXCLUDED.key_hash RETURNING * INTO bk;
  IF bk.frozen THEN
    RETURN jsonb_build_object('ok', false, 'bot_id', bot, 'error', format('Key frozen: %s, %s', coalesce(bk.freeze_reason, 'no reason'), to_char(bk.freeze_date AT TIME ZONE 'America/Los_Angeles', 'YYYY-MM-DD HH24:MI "PT"')));
  END IF;

  fid := null;
  WITH picked AS (
    SELECT q.firm_id
      FROM public.v2_research_assignments q
      JOIN public.v2_firms f ON f.firm_id = q.firm_id
     WHERE q.done_at IS NULL
       AND NOT coalesce(f.archived, false)
       AND (
         q.claimed_by IS NULL
         OR coalesce(q.expires_at, q.claimed_at + interval '6 hours') <= now()
       )
     ORDER BY CASE q.priority WHEN 'top' THEN 0 ELSE 1 END, q.firm_id
     FOR UPDATE OF q SKIP LOCKED
     LIMIT 1
  )
  UPDATE public.v2_research_assignments a
     SET claimed_by = bot,
         claimed_at = now(),
         expires_at = now() + interval '6 hours'
    FROM picked
   WHERE a.firm_id = picked.firm_id
  RETURNING a.firm_id INTO fid;

  IF fid IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'bot_id', bot, 'none_left', true);
  END IF;

  SELECT * INTO frm FROM public.v2_firms WHERE firm_id = fid;
  RETURN jsonb_build_object(
    'ok', true,
    'bot_id', bot,
    'firm_id', frm.firm_id,
    'slug', frm.slug,
    'name', frm.display_name,
    'website', frm.website_url);
END
$function$;
$claim$;

  execute $live$
create or replace function public.v2_firm_live_on_insert()
returns trigger
language plpgsql
security definer
set search_path to public
as $body$
begin
  if nullif(btrim(new.slug::text), '') is null then
    return new;
  end if;
  if coalesce(new.demand_hidden, false) then
    return new;
  end if;
  insert into public.v2_firm_live (firm_id, slug)
  values (new.firm_id, lower(btrim(new.slug::text)))
  on conflict (firm_id) do nothing;
  return new;
end
$body$
$live$;

  execute $liveid$
create or replace function public._v2_live_id(p_slug text)
returns bigint
language sql
stable
security definer
set search_path to public
as $body$
  select f.firm_id
    from public.v2_firm_live l
    join public.v2_firms f on f.firm_id = l.firm_id
   where l.slug = lower(btrim(coalesce(p_slug, '')))
     and not coalesce(f.archived, false)
     and not coalesce(f.demand_hidden, false)
   limit 1
$body$
$liveid$;

  if to_regclass('public.v2_firm_types_firms') is not null and to_regclass('public.v2_firm_type') is not null then
    execute $meta$
create or replace function public.firm_meta(p_slug text)
returns table(slug text, name text, short_name text, hq text, firm_type text, legal_name text, primary_domain text, founded_year integer, updated_at timestamptz, indexable boolean)
language sql
stable
security definer
set search_path to public, pg_temp
as $body$
  select f.slug::text, f.display_name::text, f.short_name::text,
         nullif(concat_ws(', ', f.hq_city, coalesce(f.hq_state, f.hq_country)), ''),
         (select t.name::text from v2_firm_types_firms tf join v2_firm_type t on t.firm_type_id = tf.firm_type_id where tf.firm_id = f.firm_id limit 1),
         f.legal_name::text,
         regexp_replace(regexp_replace(coalesce(f.website_url, ''), '^https?://(www\.)?', ''), '/.*$', ''),
         f.founded_year::int,
         greatest(l.live_since, f.last_checked_date::timestamptz),
         true
    from v2_firm_live l
    join v2_firms f on f.firm_id = l.firm_id
   where l.slug = lower(btrim(coalesce(p_slug, '')))
     and not coalesce(f.archived, false)
     and not coalesce(f.demand_hidden, false)
   limit 1
$body$
$meta$;
  end if;

  execute $map$
create or replace function public.firm_sitemap(p_page integer default 1, p_size integer default 10000)
returns table(slug text, updated_at timestamptz, total bigint)
language sql
stable
security definer
set search_path to public, pg_temp
as $body$
  with pub as (
    select l.slug::text as slug, l.live_since as updated_at
      from public.v2_firm_live l
      join public.v2_firms f on f.firm_id = l.firm_id
     where not coalesce(f.archived, false)
       and not coalesce(f.demand_hidden, false)
  )
  select p.slug, p.updated_at, (select count(*) from pub)
    from pub p
   order by p.slug
   offset greatest(coalesce(p_page, 1) - 1, 0) * least(greatest(coalesce(p_size, 10000), 1), 10000)
   limit least(greatest(coalesce(p_size, 10000), 1), 10000)
$body$
$map$;

  execute $sug$
create or replace function public.firm_suggest(q text)
returns json
language sql
stable
security definer
set search_path to public
as $body$
  with t as (select lower(trim(q)) t), pub as (
    select f.slug::text as slug,
           f.display_name::text as name,
           f.short_name::text as short_name,
           nullif(concat_ws(', ', f.hq_city, coalesce(f.hq_state, f.hq_country)), '') as hq
      from public.v2_firm_live l
      join public.v2_firms f on f.firm_id = l.firm_id
     where not coalesce(f.archived, false)
       and not coalesce(f.demand_hidden, false)
  ), m as (
    select f.slug, f.name, f.short_name, f.hq,
      case when lower(coalesce(f.name, '')) like t || '%'
             or lower(coalesce(f.short_name, '')) like t || '%'
             or lower(f.slug) like t || '%' then 0
           when lower(coalesce(f.name, '')) ~ ('\m' || regexp_replace(t, '([^a-z0-9 ])', '\\\1', 'g')) then 1
           else 2 end r
      from pub f, t
     where length(t) > 0
       and (lower(coalesce(f.name, '')) like '%' || t || '%'
            or lower(coalesce(f.short_name, '')) like '%' || t || '%'
            or lower(f.slug) like '%' || t || '%')
  )
  select coalesce(json_agg(json_build_object('slug', slug, 'name', name, 'short_name', short_name, 'hq', hq) order by r, name), '[]')
    from (select * from m order by r, name limit 8) x
$body$
$sug$;

  if to_regclass('public.v2_auto_published') is not null
     and to_regclass('public.v2_deals') is not null
     and to_regclass('public.v2_firm_industries') is not null
     and to_regclass('public.v2_firm_stages') is not null
     and to_regclass('public.v2_legal_items') is not null
     and to_regclass('public.v2_sector') is not null
     and to_regclass('public.v2_startup_sectors') is not null
     and to_regclass('public.v2_startups') is not null then
    execute $dir$
create or replace function public.firm_directory()
returns json
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $body$
  with live as (
    select f.firm_id, l.slug, l.live_since, f.display_name, f.short_name, f.website_url,
           f.hq_city, f.hq_state, upper(btrim(f.hq_country)) as hq_country, coalesce(nullif(f.firm_status,''),'Active') as firm_status
      from v2_firm_live l join v2_firms f on f.firm_id = l.firm_id
     where not coalesce(f.archived,false) and f.merged_into_firm_id is null
       and not coalesce(f.demand_hidden, false)
  ),
  d as (
    select d.firm_id, s.startup_id, s.startup_name, s.domain, d.round, d.deal_date, coalesce(d.lead='yes',false) as led
      from v2_deals d join v2_startups s on s.startup_id = d.startup_id and s.is_current and not s.archived
     where d.firm_id in (select firm_id from live) and d.is_current and not d.archived
       and coalesce(d.shown,true) and not d.nothing_found and d.deal_date is not null
  ),
  dagg as (
    select firm_id, count(*) as deals,
           count(*) filter (where deal_date >= current_date - 365) as deals_12m,
           count(*) filter (where deal_date >= current_date - 365 and led) as led_12m,
           array_agg(distinct startup_name) filter (where startup_name is not null) as startups,
           array_agg(distinct domain) filter (where nullif(domain,'') is not null) as startup_sites
      from d group by firm_id
  ),
  latest as (
    select distinct on (firm_id) firm_id, startup_name, round, deal_date
      from d order by firm_id, deal_date desc, startup_name
  ),
  inds as (
    select i.firm_id, json_agg(i.industry_text order by i.position, i.id) as industries
      from v2_firm_industries i
     where i.firm_id in (select firm_id from live) and i.is_current and not i.archived and nullif(btrim(i.industry_text),'') is not null
     group by i.firm_id
  ),
  dsec as (
    select firm_id, json_agg(name order by n desc, name) as industries from (
      select d.firm_id, sc.name, count(*) n
        from d join v2_startup_sectors ss on ss.startup_id = d.startup_id and ss.is_current and not ss.archived
        join v2_sector sc on sc.sector_id = ss.sector_id
       group by 1,2) x group by firm_id
  ),
  stg as (
    select firm_id, json_agg(distinct stage) as stages
      from v2_firm_stages where firm_id in (select firm_id from live) and is_current and not archived and nullif(btrim(stage),'') is not null
     group by firm_id
  ),
  leg as (
    select firm_id, count(*) as n from v2_legal_items
     where firm_id in (select firm_id from live) and is_current and not archived and not nothing_found and not coalesce(lead_only,false)
     group by firm_id
  ),
  pub as (
    select firm_id, max(applied_at) as last_fact
      from v2_auto_published
     where firm_id in (select firm_id from live)
     group by firm_id
  )
  select coalesce(json_agg(json_build_object(
      'slug', l.slug, 'name', l.display_name, 'short_name', nullif(l.short_name,''), 'website', l.website_url,
      'city', l.hq_city, 'state', l.hq_state, 'country', case when l.hq_country ~ '^[A-Z]{2}$' then l.hq_country end,
      'added', coalesce(p.last_fact, l.live_since), 'firm_status', l.firm_status,
      'industries', coalesce(i.industries, ds.industries, '[]'::json),
      'stages', coalesce(st.stages, '[]'::json),
      'deals', coalesce(a.deals,0), 'deals_12m', coalesce(a.deals_12m,0), 'led_12m', coalesce(a.led_12m,0),
      'latest_company', lt.startup_name, 'latest_round', lt.round, 'latest_deal_date', lt.deal_date,
      'legal_records', coalesce(lg.n,0), 'legal_status', case when lg.n > 0 then 'has' else 'unknown' end,
      'startups', coalesce(to_json(a.startups), '[]'::json), 'startup_sites', coalesce(to_json(a.startup_sites), '[]'::json)
    ) order by coalesce(p.last_fact, l.live_since) desc, l.display_name), '[]'::json)
    from live l
    left join dagg a on a.firm_id = l.firm_id
    left join latest lt on lt.firm_id = l.firm_id
    left join inds i on i.firm_id = l.firm_id
    left join dsec ds on ds.firm_id = l.firm_id
    left join stg st on st.firm_id = l.firm_id
    left join leg lg on lg.firm_id = l.firm_id
    left join pub p on p.firm_id = l.firm_id
$body$
$dir$;
  end if;

  execute 'create index if not exists research_queue_name_exact_idx on public.research_queue (lower(regexp_replace(btrim(name), ''\s+'', '' '', ''g'')))';
  execute 'create index if not exists research_queue_website_domain_idx on public.research_queue (public._req_domain(website)) where website is not null';

  execute $wanted$
create table if not exists public.v2_search_wanted (
  term_norm text primary key,
  term text not null,
  last_seen timestamptz not null default now(),
  searches integer not null default 0,
  watches integer not null default 0
)
$wanted$;
  execute 'alter table public.v2_search_wanted enable row level security';
  execute 'revoke all on table public.v2_search_wanted from public, anon, authenticated';
  execute $wc$
comment on table public.v2_search_wanted is
  'Search terms with no single exact firm in v2 or research_queue. For Alex. Not shown on the site.'
$wc$;

  execute $cur$
create table if not exists public.v2_search_demand_cursor (
  id integer primary key check (id = 1),
  last_log_id bigint not null default 0,
  last_watch_id bigint not null default 0,
  ran_at timestamptz
)
$cur$;
  execute 'insert into public.v2_search_demand_cursor (id) values (1) on conflict do nothing';
  execute 'alter table public.v2_search_demand_cursor enable row level security';
  execute 'revoke all on table public.v2_search_demand_cursor from public, anon, authenticated';

  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant select, insert, update, delete on table public.v2_search_wanted, public.v2_search_demand_cursor to service_role';
  end if;

  execute $go$
create or replace function public.v2_search_go_live(p_firm_id bigint)
returns void
language plpgsql
security definer
set search_path to public
as $body$
declare slg text;
begin
  update public.v2_firms
     set demand_hidden = false
   where firm_id = p_firm_id
     and demand_hidden
     and not coalesce(archived, false);
  select lower(btrim(slug::text)) into slg
    from public.v2_firms
   where firm_id = p_firm_id
     and not coalesce(archived, false)
     and not coalesce(demand_hidden, false);
  if slg is null or slg = '' then
    return;
  end if;
  begin
    insert into public.v2_firm_live (firm_id, slug)
    values (p_firm_id, slg)
    on conflict (firm_id) do nothing;
  exception when unique_violation then
    update public.v2_firms set demand_hidden = true where firm_id = p_firm_id;
    raise warning 'v2_search_go_live: slug % already live on another firm', slg;
  end;
end
$body$
$go$;

  execute $trgfn$
create or replace function public.v2_research_done_go_live()
returns trigger
language plpgsql
security definer
set search_path to public
as $body$
begin
  if new.done_at is not null and old.done_at is null
     and exists (
       select 1 from public.v2_firms f
        where f.firm_id = new.firm_id and f.demand_hidden
     ) then
    perform public.v2_search_go_live(new.firm_id);
  end if;
  return null;
end
$body$
$trgfn$;
  execute 'drop trigger if exists v2_research_done_go_live on public.v2_research_assignments';
  execute $trg$
create trigger v2_research_done_go_live
  after update of done_at on public.v2_research_assignments
  for each row execute function public.v2_research_done_go_live()
$trg$;

  execute $note$
create or replace function public.v2_search_wanted_note(p_norm text, p_term text)
returns void
language plpgsql
security definer
set search_path to public
as $body$
begin
  insert into public.v2_search_wanted (term_norm, term, last_seen, searches, watches)
  values (
    p_norm,
    left(btrim(coalesce(p_term, p_norm)), 100),
    now(),
    (select count(*)::int from public.v2_search_log where term_norm = p_norm),
    (select count(*)::int from public.v2_firm_watch where term_norm = p_norm)
  )
  on conflict (term_norm) do update
    set term = excluded.term,
        last_seen = excluded.last_seen,
        searches = excluded.searches,
        watches = excluded.watches;
end
$body$
$note$;

  execute $attach$
create or replace function public.v2_search_attach(p_firm_id bigint, p_registry text, p_norm text, p_term text)
returns void
language plpgsql
security definer
set search_path to public
as $body$
begin
  if p_firm_id is null or length(coalesce(p_norm, '')) < 2 then
    return;
  end if;
  if exists (
    select 1 from public.v2_research_assignments
     where firm_id = p_firm_id and done_at is not null
  ) then
    if exists (select 1 from public.v2_firms where firm_id = p_firm_id and demand_hidden) then
      perform public.v2_search_go_live(p_firm_id);
    end if;
  else
    insert into public.v2_research_assignments (firm_id, priority)
    values (p_firm_id, 'top')
    on conflict (firm_id) do update
      set priority = 'top'
      where public.v2_research_assignments.done_at is null
        and public.v2_research_assignments.priority is distinct from 'top';
  end if;
  update public.v2_firm_watch
     set firm_id = p_firm_id,
         registry_id = coalesce(registry_id, p_registry)
   where term_norm = p_norm
     and firm_id is null;
  insert into public.v2_firm_watch (term, term_norm, registry_id, firm_id, user_id)
  select distinct on (s.user_id)
         left(s.term, 100), s.term_norm, p_registry, p_firm_id, s.user_id
    from public.v2_search_log s
   where s.term_norm = p_norm
     and s.user_id is not null
     and s.result_count = 0
     and not exists (
       select 1 from public.v2_firm_watch w
        where w.term_norm = s.term_norm and w.user_id = s.user_id
     )
   order by s.user_id, s.id
   limit 200
  on conflict (term_norm, user_id) where user_id is not null do nothing;
  delete from public.v2_search_wanted where term_norm = p_norm;
end
$body$
$attach$;

  execute $one$
create or replace function public.v2_search_demand_one(p_term text)
returns jsonb
language plpgsql
security definer
set search_path to public
set statement_timeout to '8s'
set lock_timeout to '2s'
as $body$
declare
  v_term text := left(regexp_replace(btrim(coalesce(p_term, '')), '\s+', ' ', 'g'), 100);
  v_norm text := public.v2_search_norm(p_term);
  v_key text := public._queue_name_key(v_norm);
  v_dom text := public._req_domain(v_norm);
  v_fid bigint;
  v_n int;
  v_reg text;
  v_name text;
  v_web text;
  v_slug text;
  v_base text;
  v_i int;
begin
  if length(coalesce(v_norm, '')) < 2 then
    return jsonb_build_object('ok', true, 'status', 'ignored');
  end if;

  select count(*)::int into v_n from (
    select f.firm_id
      from public.v2_firms f
     where not coalesce(f.archived, false)
       and f.merged_into_firm_id is null
       and (
         (length(coalesce(v_key, '')) >= 2 and (
            public._queue_name_key(f.display_name) = v_key
            or public._queue_name_key(f.short_name) = v_key
            or public._queue_name_key(f.legal_name) = v_key
         ))
         or lower(regexp_replace(btrim(f.display_name), '\s+', ' ', 'g')) = v_norm
         or lower(regexp_replace(btrim(coalesce(f.short_name, '')), '\s+', ' ', 'g')) = v_norm
         or lower(btrim(f.slug::text)) = v_norm
         or (v_dom is not null and public._req_domain(f.website_url) = v_dom)
       )
     limit 3
  ) hits;

  if v_n > 1 then
    perform public.v2_search_wanted_note(v_norm, v_term);
    return jsonb_build_object('ok', true, 'status', 'ambiguous');
  end if;

  if v_n = 1 then
    select f.firm_id into v_fid
      from public.v2_firms f
     where not coalesce(f.archived, false)
       and f.merged_into_firm_id is null
       and (
         (length(coalesce(v_key, '')) >= 2 and (
            public._queue_name_key(f.display_name) = v_key
            or public._queue_name_key(f.short_name) = v_key
            or public._queue_name_key(f.legal_name) = v_key
         ))
         or lower(regexp_replace(btrim(f.display_name), '\s+', ' ', 'g')) = v_norm
         or lower(regexp_replace(btrim(coalesce(f.short_name, '')), '\s+', ' ', 'g')) = v_norm
         or lower(btrim(f.slug::text)) = v_norm
         or (v_dom is not null and public._req_domain(f.website_url) = v_dom)
       )
     order by f.firm_id
     limit 1;
    perform public.v2_search_attach(v_fid, null, v_norm, v_term);
    return jsonb_build_object('ok', true, 'status', 'matched', 'firm_id', v_fid, 'created', false);
  end if;

  select count(*)::int into v_n from (
    select q.registry_id
      from public.research_queue q
     where q.duplicate_of is null
       and (
         (length(coalesce(v_key, '')) >= 2 and q.name_key = v_key)
         or lower(regexp_replace(btrim(q.name), '\s+', ' ', 'g')) = v_norm
         or (v_dom is not null and public._req_domain(q.website) = v_dom)
       )
     limit 3
  ) hits;

  if v_n > 1 then
    perform public.v2_search_wanted_note(v_norm, v_term);
    return jsonb_build_object('ok', true, 'status', 'ambiguous');
  end if;
  if v_n = 0 then
    perform public.v2_search_wanted_note(v_norm, v_term);
    return jsonb_build_object('ok', true, 'status', 'wanted');
  end if;

  select q.registry_id, left(btrim(q.name), 200), nullif(btrim(q.website), '')
    into v_reg, v_name, v_web
    from public.research_queue q
   where q.duplicate_of is null
     and (
       (length(coalesce(v_key, '')) >= 2 and q.name_key = v_key)
       or lower(regexp_replace(btrim(q.name), '\s+', ' ', 'g')) = v_norm
       or (v_dom is not null and public._req_domain(q.website) = v_dom)
     )
   order by q.registry_id
   limit 1;

  if v_name is null or v_name = '' then
    perform public.v2_search_wanted_note(v_norm, v_term);
    return jsonb_build_object('ok', true, 'status', 'wanted');
  end if;

  if v_web is not null then
    select f.firm_id into v_fid
      from public.v2_firms f
     where not coalesce(f.archived, false)
       and f.merged_into_firm_id is null
       and (
         f.website_url_norm = public.v2_norm_url(v_web)
         or public._req_domain(f.website_url) = public._req_domain(v_web)
       )
     order by f.firm_id
     limit 1;
  end if;
  if v_fid is null then
    select count(*)::int into v_n from (
      select f.firm_id
        from public.v2_firms f
       where not coalesce(f.archived, false)
         and f.merged_into_firm_id is null
         and (
           public._queue_name_key(f.display_name) = public._queue_name_key(v_name)
           or lower(regexp_replace(btrim(f.display_name), '\s+', ' ', 'g')) = lower(regexp_replace(btrim(v_name), '\s+', ' ', 'g'))
         )
       limit 3
    ) hits;
    if v_n > 1 then
      perform public.v2_search_wanted_note(v_norm, v_term);
      return jsonb_build_object('ok', true, 'status', 'ambiguous');
    end if;
    if v_n = 1 then
      select f.firm_id into v_fid
        from public.v2_firms f
       where not coalesce(f.archived, false)
         and f.merged_into_firm_id is null
         and (
           public._queue_name_key(f.display_name) = public._queue_name_key(v_name)
           or lower(regexp_replace(btrim(f.display_name), '\s+', ' ', 'g')) = lower(regexp_replace(btrim(v_name), '\s+', ' ', 'g'))
         )
       order by f.firm_id
       limit 1;
    end if;
  end if;

  if v_fid is not null then
    perform public.v2_search_attach(v_fid, v_reg, v_norm, v_term);
    return jsonb_build_object('ok', true, 'status', 'matched', 'firm_id', v_fid, 'created', false);
  end if;

  if v_web is not null and (
    v_web !~* '^(https?://)?(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)+(:[0-9]+)?(/[^\s]*)?$'
    or public.v2_url_never_website(v_web)
  ) then
    v_web := null;
  end if;

  v_base := left(regexp_replace(coalesce(public._slugify(v_name), ''), '-+$', ''), 180);
  if v_base is null or v_base = '' then
    perform public.v2_search_wanted_note(v_norm, v_term);
    return jsonb_build_object('ok', true, 'status', 'wanted');
  end if;
  v_slug := v_base;
  v_i := 1;
  while exists (select 1 from public.v2_firms where slug = v_slug) loop
    v_i := v_i + 1;
    exit when v_i > 20;
    v_slug := left(v_base, 180) || '-' || v_i;
  end loop;
  if exists (select 1 from public.v2_firms where slug = v_slug) then
    perform public.v2_search_wanted_note(v_norm, v_term);
    return jsonb_build_object('ok', true, 'status', 'wanted');
  end if;

  begin
    insert into public.v2_firms (slug, display_name, website_url, firm_status, demand_hidden)
    values (v_slug, v_name, v_web, 'Active', true)
    returning firm_id into v_fid;
  exception when unique_violation then
    select f.firm_id into v_fid
      from public.v2_firms f
     where not coalesce(f.archived, false)
       and (f.slug = v_slug or (v_web is not null and f.website_url_norm = public.v2_norm_url(v_web)))
     order by f.firm_id
     limit 1;
    if v_fid is null then
      perform public.v2_search_wanted_note(v_norm, v_term);
      return jsonb_build_object('ok', true, 'status', 'wanted');
    end if;
    perform public.v2_search_attach(v_fid, v_reg, v_norm, v_term);
    return jsonb_build_object('ok', true, 'status', 'matched', 'firm_id', v_fid, 'created', false);
  end;

  perform public.v2_search_attach(v_fid, v_reg, v_norm, v_term);
  return jsonb_build_object('ok', true, 'status', 'queued', 'firm_id', v_fid, 'created', true);
end
$body$
$one$;

  execute $run$
create or replace function public.v2_search_demand_run()
returns jsonb
language plpgsql
security definer
set search_path to public
set statement_timeout to '8s'
set lock_timeout to '2s'
as $body$
declare
  rec record;
  n int := 0;
  last_log bigint;
  last_watch bigint;
begin
  insert into public.v2_search_demand_cursor (id) values (1) on conflict do nothing;
  select c.last_log_id, c.last_watch_id into last_log, last_watch
    from public.v2_search_demand_cursor c
   where c.id = 1
   for update skip locked;
  if not found then
    return jsonb_build_object('ok', true, 'busy', true);
  end if;

  for rec in
    select id, term from public.v2_search_log
     where id > last_log
     order by id
     limit 20
  loop
    begin
      perform public.v2_search_demand_one(rec.term);
    exception when others then
      raise warning 'v2_search_demand log %: %', rec.id, sqlerrm;
    end;
    last_log := rec.id;
    n := n + 1;
  end loop;

  for rec in
    select id, term from public.v2_firm_watch
     where id > last_watch and firm_id is null
     order by id
     limit 20
  loop
    begin
      perform public.v2_search_demand_one(rec.term);
    exception when others then
      raise warning 'v2_search_demand watch %: %', rec.id, sqlerrm;
    end;
    last_watch := rec.id;
    n := n + 1;
  end loop;

  for rec in
    select term from public.v2_search_wanted
     order by last_seen
     limit 10
  loop
    begin
      perform public.v2_search_demand_one(rec.term);
    exception when others then
      raise warning 'v2_search_demand wanted: %', sqlerrm;
    end;
    n := n + 1;
  end loop;

  update public.v2_search_demand_cursor
     set last_log_id = last_log, last_watch_id = last_watch, ran_at = now()
   where id = 1;
  return jsonb_build_object('ok', true, 'seen', n);
end
$body$
$run$;

  execute $box$
create or replace function public.ondemand_outbox(p_limit integer default 50)
returns table(id bigint, kind text, email text, name text, slug text)
language sql
stable
security definer
set search_path to public
as $body$
  select * from (
    select r.id,
           case when r.status = 'refunded' then 'refund'
                when r.spend_kind = 'request' and r.firm_request_id is not null then 'ready_request'
                else 'ready' end kind,
           r.email, coalesce(f.display_name, f.name) name, f.slug
      from research_requests r join firms f on f.id = r.firm_id
     where r.status in ('done', 'refunded') and r.email is not null and r.notified_at is null and r.notify_error is null
       and f.published and f.deleted_at is null and f.data_status = 'real' and not coalesce(f.is_test, false)
    union all
    select e.id, 'received', e.email, q.name, null::text
      from firm_request_emails e join firm_requests q on q.id = e.request_id
     where e.received_notified_at is null and e.notify_error is null and e.research_request_id is null
       and e.created_at > now() - interval '2 days'
    union all
    select s.id, 'search_live', s.email, s.name, s.slug
      from (
        select distinct on (x.firm_id, lower(x.email))
               x.id, x.email, x.name, x.slug
          from (
            select w.id, f.firm_id,
                   coalesce(w.email, u.email) as email,
                   f.display_name::text as name,
                   l.slug::text as slug
              from v2_firm_watch w
              join v2_firms f on f.firm_id = w.firm_id
              join v2_firm_live l on l.firm_id = f.firm_id
              left join auth.users u on u.id = w.user_id
             where w.notified_at is null
               and w.notify_error is null
               and not coalesce(f.archived, false)
               and not coalesce(f.demand_hidden, false)
          ) x
         where nullif(btrim(x.email), '') is not null
         order by x.firm_id, lower(x.email), x.id
      ) s
  ) y
  order by kind = 'received', id
  limit greatest(1, least(coalesce(p_limit, 50), 200))
$body$
$box$;

  execute $mark$
create or replace function public.ondemand_mark_notified(p_id bigint, p_error text default null, p_kind text default null)
returns void
language plpgsql
security definer
set search_path to public
as $body$
begin
  if p_kind = 'received' then
    update firm_request_emails
       set received_notified_at = case when p_error is null then now() end,
           notify_error = left(p_error, 500)
     where id = p_id;
  elsif p_kind = 'search_live' then
    update v2_firm_watch w
       set notified_at = case when p_error is null then now() else w.notified_at end,
           notify_error = left(p_error, 500)
      from (
        select t.id, t.firm_id,
               lower(coalesce(t.email, (select u.email from auth.users u where u.id = t.user_id))) as em
          from v2_firm_watch t
         where t.id = p_id
      ) src
     where w.notified_at is null
       and w.notify_error is null
       and (
         w.id = src.id
         or (
           src.firm_id is not null
           and w.firm_id = src.firm_id
           and lower(coalesce(w.email, (select u.email from auth.users u where u.id = w.user_id))) = src.em
         )
       );
  else
    update research_requests
       set notified_at = case when p_error is null then now() end,
           notify_error = left(p_error, 500)
     where id = p_id;
    update check_requests
       set notified_at = coalesce(notified_at, case when p_error is null then now() end),
           status = case when p_error is null then 'done' else status end
     where research_request_id = p_id;
  end if;
end
$body$
$mark$;

  execute 'revoke all on function public.v2_search_go_live(bigint) from public, anon, authenticated';
  execute 'revoke all on function public.v2_research_done_go_live() from public, anon, authenticated';
  execute 'revoke all on function public.v2_search_wanted_note(text, text) from public, anon, authenticated';
  execute 'revoke all on function public.v2_search_attach(bigint, text, text, text) from public, anon, authenticated';
  execute 'revoke all on function public.v2_search_demand_one(text) from public, anon, authenticated';
  execute 'revoke all on function public.v2_search_demand_run() from public, anon, authenticated';
  execute 'revoke all on function public.ondemand_outbox(integer) from public, anon, authenticated';
  execute 'revoke all on function public.ondemand_mark_notified(bigint, text, text) from public, anon, authenticated';
  execute 'revoke all on function public.v2_firm_live_on_insert() from public, anon, authenticated';
  execute 'revoke all on function public._v2_live_id(text) from public, anon, authenticated';
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.v2_search_go_live(bigint) to service_role';
    execute 'grant execute on function public.v2_search_demand_one(text) to service_role';
    execute 'grant execute on function public.v2_search_demand_run() to service_role';
    execute 'grant execute on function public.ondemand_outbox(integer) to service_role';
    execute 'grant execute on function public.ondemand_mark_notified(bigint, text, text) to service_role';
    execute 'grant execute on function public.v2_firm_live_on_insert() to service_role';
  end if;

  if to_regclass('cron.job') is not null then
    if exists (select 1 from cron.job where jobname = 'v2-search-demand') then
      perform cron.unschedule('v2-search-demand');
    end if;
    perform cron.schedule('v2-search-demand', '0 */6 * * *', 'select public.v2_search_demand_run()');
  end if;
end
$mig$;
