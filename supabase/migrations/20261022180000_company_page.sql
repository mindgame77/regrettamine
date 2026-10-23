-- Company page (/vc/<slug>/) + search dropdown.
-- Backup before this migration: toxybase/backups/2026-10-22-profile/ (tag pre-company-page).
-- One read RPC per page: firm_page(slug, anon, spend). Locked pages get counts + one teaser line per section only.

alter table firms add column if not exists launch_page boolean not null default false;
update firms set launch_page = true where slug in ('a16z', 'nb-alternatives');

alter table press_items add column if not exists snippet text, add column if not exists logo_path text;
alter table fact_sources add column if not exists date_label text;
create index if not exists fact_sources_fact_idx on fact_sources (fact_type, fact_id, sort_order);

-- Every row below is shown only with at least one fact_sources row (fact_type = table name, fact_id = id).
create table if not exists firm_profile_facts (
  id uuid primary key default gen_random_uuid(), firm_id uuid not null references firms(id) on delete cascade,
  section text not null check (section in ('overview', 'funds')), label text not null, value text not null,
  hero_label text, hero_value text, sort_order int not null default 0);
create table if not exists firm_legal_items (
  id uuid primary key default gen_random_uuid(), firm_id uuid not null references firms(id) on delete cascade,
  grp text not null check (grp in ('case', 'regulator', 'context')), title text not null, year_label text, role text,
  state text check (state in ('Active', 'Closed', 'Unverified')), status_label text, tone text check (tone in ('rev', 'ok', 'g')),
  note text, sort_order int not null default 0);
create table if not exists founder_accounts (
  id uuid primary key default gen_random_uuid(), firm_id uuid not null references firms(id) on delete cascade,
  outlet text not null, date_label text, headline text not null, url text not null, snippet text, sort_order int not null default 0);
create table if not exists firm_people_roles (
  id uuid primary key default gen_random_uuid(), firm_id uuid not null references firms(id) on delete cascade,
  kind text not null check (kind in ('board', 'move', 'officer')), person_name text not null, role text not null, badge text,
  sort_order int not null default 0);
create table if not exists timeline_events (
  id uuid primary key default gen_random_uuid(), firm_id uuid not null references firms(id) on delete cascade,
  date_label text not null, kind text not null, body text not null, sort_order int not null default 0);
create table if not exists firm_check_rows (
  firm_id uuid not null references firms(id) on delete cascade, n int not null check (n between 1 and 10),
  title text not null, descr text not null, state text not null, count_label text, primary key (firm_id, n));
-- Section config: order, title, renderer and units live here; the page renders whatever is enabled and non-empty.
create table if not exists page_sections (
  key text primary key, sort_order int not null, title text not null, subtitle text, renderer text not null,
  unit_one text not null, unit_many text not null, enabled boolean not null default true);

do $$ declare t text; begin
  foreach t in array array['firm_profile_facts','firm_legal_items','founder_accounts','firm_people_roles','timeline_events','firm_check_rows'] loop
    execute format('create index if not exists %I on %I (firm_id)', t || '_firm_idx', t);
  end loop;
  foreach t in array array['firm_profile_facts','firm_legal_items','founder_accounts','firm_people_roles','timeline_events','firm_check_rows','page_sections'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from anon, authenticated', t);
  end loop;
end $$;

insert into page_sections (key, sort_order, title, subtitle, renderer, unit_one, unit_many) values
  ('overview', 10, 'Overview', 'Registration and ownership from the firm''s own filings.', 'facts', 'fact', 'facts'),
  ('checks', 20, 'The 10 checks', 'Sanctions, regulators, courts, registration and people.', 'checks', 'check', 'checks'),
  ('legal', 30, 'Legal & regulatory', 'Cases where the firm itself is a party, and regulator records.', 'legal', 'record', 'records'),
  ('press', 40, 'Press coverage', 'Articles naming the firm, with the outlet and date.', 'press', 'article', 'articles'),
  ('founders', 50, 'What founders say', 'Accounts from founders, each with its source.', 'founders', 'account', 'accounts'),
  ('people', 60, 'People & board seats', 'Officers, partner moves and board seats.', 'people', 'person', 'people'),
  ('funds', 70, 'Firm & funds', 'Assets and funds from Form ADV.', 'facts', 'fact', 'facts'),
  ('timeline', 80, 'Timeline', 'Dated events with a source.', 'timeline', 'event', 'events')
on conflict (key) do update set sort_order = excluded.sort_order, title = excluded.title, subtitle = excluded.subtitle,
  renderer = excluded.renderer, unit_one = excluded.unit_one, unit_many = excluded.unit_many;

create or replace function _src(p_type text, p_id uuid) returns jsonb language sql stable set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('label', coalesce(fs.label, s.publisher), 'date', fs.date_label, 'url', s.url) order by fs.sort_order), '[]')
  from fact_sources fs join sources s on s.id = fs.source_id where fs.fact_type = p_type and fs.fact_id = p_id
$$;

-- Items of one section. Each item has 'head' (the one line shown while locked) and 'src' (non-empty).
create or replace function _sec_items(p_key text, p_firm uuid) returns jsonb language sql stable set search_path = public as $$
  select coalesce(jsonb_agg(it order by o), '[]') from (
    select jsonb_build_object('head', label || ': ' || value, 'label', label, 'value', value, 'src', _src('firm_profile_facts', id)) it, sort_order o
      from firm_profile_facts where firm_id = p_firm and section = p_key and p_key in ('overview', 'funds')
    union all
    select jsonb_build_object('head', 'Check ' || n || ': ' || title, 'n', n, 'title', title, 'descr', descr, 'state', state, 'count', count_label, 'src', '[]'::jsonb), n
      from firm_check_rows where firm_id = p_firm and p_key = 'checks'
    union all
    select jsonb_build_object('head', title, 'grp', grp, 'year', year_label, 'role', role, 'state', state, 'status', status_label, 'tone', tone, 'note', note,
        'src', _src('firm_legal_items', id)), case grp when 'case' then 0 when 'regulator' then 1000 else 2000 end + sort_order
      from firm_legal_items where firm_id = p_firm and p_key = 'legal'
    union all
    select jsonb_build_object('head', p.headline, 'outlet', p.publisher, 'date', p.published_label, 'url', p.url, 'snippet', p.snippet, 'logo', p.logo_path, 'group', p.group_label,
        'src', jsonb_build_array(jsonb_build_object('label', p.publisher, 'date', p.published_label, 'url', p.url))), pf.sort_order
      from press_items p join press_item_firms pf on pf.press_item_id = p.id
      where pf.firm_id = p_firm and p_key = 'press' and p.data_status = 'real' and p.url <> ''
    union all
    select jsonb_build_object('head', headline, 'outlet', outlet, 'date', date_label, 'url', url, 'snippet', snippet, 'src', _src('founder_accounts', id)), sort_order
      from founder_accounts where firm_id = p_firm and p_key = 'founders'
    union all
    select jsonb_build_object('head', person_name, 'kind', kind, 'role', role, 'badge', badge, 'src', _src('firm_people_roles', id)),
        case kind when 'board' then 0 when 'move' then 1000 else 2000 end + sort_order
      from firm_people_roles where firm_id = p_firm and p_key = 'people'
    union all
    select jsonb_build_object('head', date_label || ' · ' || body, 'date', date_label, 'kind', kind, 'body', body, 'src', _src('timeline_events', id)), sort_order
      from timeline_events where firm_id = p_firm and p_key = 'timeline'
  ) x where p_key in ('checks', 'press') or jsonb_array_length(it->'src') > 0
$$;

create or replace function unlock_firm(p_slug text, p_anon uuid, p_spend boolean default true) returns json
language plpgsql security definer set search_path = public as $function$
declare b public.check_balances := _balance(p_anon); f uuid; h text := _ip_hash(); ip_cap constant int := 4;
begin
  select id into f from firms where slug = p_slug and deleted_at is null and (published or launch_page);
  if f is null then return json_build_object('status','not_found'); end if;
  if not exists (select 1 from check_events where balance_id = b.id and firm_id = f and kind like 'spend_%') then
    if not p_spend then return json_build_object('status','locked'); end if;
    if b.free_left > 0 and auth.uid() is null and h is not null
       and (select count(*) from check_events where ip_hash = h and kind = 'spend_free' and created_at > now() - interval '30 days') >= ip_cap then
      return json_build_object('status','need_signup');
    end if;
    if b.free_left > 0 then
      update check_balances set free_left = free_left - 1, updated_at = now() where id = b.id;
      insert into check_events(balance_id, firm_id, kind, amount, ip_hash) values (b.id, f, 'spend_free', -1, case when auth.uid() is null then h end);
    elsif b.paid_left > 0 then
      update check_balances set paid_left = paid_left - 1, updated_at = now() where id = b.id;
      insert into check_events(balance_id, firm_id, kind, amount) values (b.id, f, 'spend_paid', -1);
    elsif auth.uid() is null then return json_build_object('status','need_signup');
    else return json_build_object('status','out');
    end if;
  end if;
  return json_build_object('status','ok','details', public.firm_details(f));
end $function$;

create or replace function firm_case_outline(p_slug text) returns json language sql stable security definer set search_path = public as $function$
  select coalesce(json_agg(json_build_object('row', rn, 'items', items) order by rn), '[]'::json) from (
    select c.rn, json_agg(json_build_object('kind', c.kind, 'year', c.yr, 'status', c.status)
      order by (c.status = 'active') desc nulls last, c.ord) items
    from firms f, public._firm_cases(f.id) c
    where f.slug = p_slug and f.deleted_at is null and (f.published or f.launch_page)
    group by c.rn) g
$function$;

-- The page RPC. p_spend=false only reads; p_spend=true spends a check (same rules as unlock_firm).
create or replace function firm_page(p_slug text, p_anon uuid, p_spend boolean default false) returns json
language plpgsql security definer set search_path = public as $$
declare f firms; u json; open boolean; secs jsonb := '[]'; s page_sections; it jsonb; hero jsonb;
begin
  select * into f from firms where slug = p_slug and deleted_at is null and launch_page;
  if f.id is null then return json_build_object('status', 'not_found'); end if;
  u := unlock_firm(p_slug, p_anon, p_spend);
  open := u->>'status' = 'ok';
  if u->>'status' not in ('ok', 'locked') then return u; end if;
  for s in select * from page_sections where enabled order by sort_order loop
    it := _sec_items(s.key, f.id);
    continue when jsonb_array_length(it) = 0;
    secs := secs || jsonb_build_object('key', s.key, 'title', s.title, 'subtitle', s.subtitle, 'renderer', s.renderer,
      'count', jsonb_array_length(it), 'unit', case when jsonb_array_length(it) = 1 then s.unit_one else s.unit_many end,
      'teaser', it->0->>'head', 'items', case when open then it end);
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('label', hero_label, 'value', hero_value, 'anchor', section,
      'src', _src('firm_profile_facts', id)) order by section desc, sort_order), '[]') into hero
    from firm_profile_facts where firm_id = f.id and hero_label is not null and exists (select 1 from fact_sources where fact_type = 'firm_profile_facts' and fact_id = firm_profile_facts.id);
  return json_build_object('status', 'ok', 'open', open,
    'firm', json_build_object('slug', f.slug, 'name', f.name, 'short_name', f.short_name, 'hq', f.hq),
    'hero', hero, 'sections', secs,
    'checks', (select json_agg(json_build_object('n', n, 'title', title, 'descr', descr, 'state', state, 'count', count_label) order by n) from firm_check_rows where firm_id = f.id),
    'details', u->'details', 'outline', case when not open then firm_case_outline(p_slug) end);
end $$;

-- Search dropdown: max 8, prefix > word start > contains.
create or replace function firm_suggest(q text) returns json language sql stable security definer set search_path = public as $$
  with t as (select lower(trim(q)) t), m as (
    select f.slug, f.name, f.short_name, f.hq,
      case when lower(f.name) like t || '%' or lower(coalesce(f.short_name, '')) like t || '%' or f.slug like t || '%' then 0
           when lower(f.name) ~ ('\m' || regexp_replace(t, '([^a-z0-9 ])', '\\\1', 'g')) then 1 else 2 end r
    from firms f, t
    where f.launch_page and f.deleted_at is null and length(t) > 0
      and (lower(f.name) like '%' || t || '%' or lower(coalesce(f.short_name, '')) like '%' || t || '%' or f.slug like '%' || t || '%'))
  select coalesce(json_agg(json_build_object('slug', slug, 'name', name, 'short_name', short_name, 'hq', hq) order by r, name), '[]')
  from (select * from m order by r, name limit 8) x
$$;

revoke all on function _src(text, uuid), _sec_items(text, uuid) from public, anon, authenticated;
grant execute on function firm_page(text, uuid, boolean), firm_suggest(text) to anon, authenticated;
