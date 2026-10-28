-- One home per data kind, lab firms only.
-- Exact copies: keep one, delete the extra, after a backup. Different values stay on the page.
-- A disagreement is one Checker review row. Side tables are not dropped and are not copied
-- onto the page, because that would add rows the page does not show today.
-- fact_events is the public fact counter (one row per inserted fact). It cannot store a
-- loser or a decision, so the permanent log is home_merge_log.
-- The backup is home_merge_backup. It is kept. Do not delete it without Alex's OK.
-- This file installs the step. It does not change rows. After Alex confirms the dry run:
--   select * from public.lab_one_home(true);
-- Rollback: supabase/rollbacks/20261028140000_one_home_lab.sql

alter table public.firm_aliases add column if not exists alias_type text;
alter table public.firm_aliases drop constraint if exists firm_aliases_alias_type_chk;
alter table public.firm_aliases add constraint firm_aliases_alias_type_chk
  check (alias_type is null or alias_type in ('display', 'legal', 'fund_entity', 'old_name'));
comment on column public.firm_aliases.alias_type is
  'display, legal, fund entity, or old name. The source column stays. The page does not read this.';

create table if not exists public.home_merge_backup (
  id bigserial primary key,
  backed_up_at timestamptz not null default now(),
  keep_until timestamptz not null default (now() + interval '3 days'),
  firm_id uuid,
  table_name text not null,
  item_key text not null,
  row_data jsonb not null
);
alter table public.home_merge_backup enable row level security;
revoke all on public.home_merge_backup from public, anon, authenticated;
comment on table public.home_merge_backup is
  'Rows copied before an exact duplicate was removed. Keep 3 days, then delete only with Alex OK. Do not drop this table from the rollback.';

create table if not exists public.home_merge_log (
  id bigserial primary key,
  firm_id uuid not null,
  kind text not null,
  item_key text not null,
  action text not null check (action in ('duplicate', 'merge', 'disagreement', 'held')),
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (firm_id, kind, item_key, action)
);
alter table public.home_merge_log enable row level security;
revoke all on public.home_merge_log from public, anon, authenticated;
comment on table public.home_merge_log is
  'Permanent log of the one-home step. fact_events is only the public fact counter and is not used here.';

create or replace function public.lab_one_home(p_write boolean default false)
returns table(slug text, kind text, duplicates int, merges int, disagreements int, held int)
language plpgsql security definer set search_path = public, bots as $$
#variable_conflict use_column
declare r record; n int;
begin
  drop table if exists pg_temp.home_drop;
  drop table if exists pg_temp.home_flag;
  create temp table home_drop (
    firm_id uuid, slug text, kind text, item_key text, table_name text, row_id uuid, keep_id uuid
  ) on commit drop;
  create temp table home_flag (
    firm_id uuid, slug text, kind text, item_key text, action text, detail jsonb
  ) on commit drop;

  insert into home_drop(firm_id, slug, kind, item_key, table_name, row_id, keep_id)
  with lab as (
    select id, slug from firms f where f.deleted_at is null and public._lab_firm(f.id)
  ), base as (
    select l.id firm_id, l.slug, public._checker_url_key(p.url) key, public._norm_txt(p.headline) txt,
           pf.press_item_id row_id, 'press_item_firms'::text table_name,
           row_number() over (partition by l.id, public._checker_url_key(p.url), public._norm_txt(p.headline)
             order by coalesce(pf.hidden, false), (pf.check_mark = 'checked_correct') desc, p.id) rn
    from lab l
    join press_item_firms pf on pf.firm_id = l.id
    join press_items p on p.id = pf.press_item_id
    where public._checker_url_key(p.url) is not null
  )
  select b.firm_id, b.slug, 'news', 'dup:press:' || b.row_id::text, b.table_name, b.row_id,
         first_value(b.row_id) over (partition by b.firm_id, b.key, b.txt order by b.rn)
  from base b where b.rn > 1;

  insert into home_drop(firm_id, slug, kind, item_key, table_name, row_id, keep_id)
  with lab as (
    select id, slug from firms f where f.deleted_at is null and public._lab_firm(f.id)
  ), base as (
    select l.id firm_id, l.slug, coalesce(public._checker_url_key(t.source_url), 'sk:' || t.stable_key) key,
           public._norm_txt(t.body) txt, t.id row_id,
           row_number() over (partition by l.id, coalesce(public._checker_url_key(t.source_url), 'sk:' || t.stable_key), public._norm_txt(t.body)
             order by coalesce(t.hidden, false), (t.check_mark = 'checked_correct') desc, t.id) rn
    from lab l join timeline_events t on t.firm_id = l.id
    where coalesce(public._checker_url_key(t.source_url), nullif(t.stable_key, '')) is not null
  )
  select b.firm_id, b.slug, 'news', 'dup:time:' || b.row_id::text, 'timeline_events', b.row_id,
         first_value(b.row_id) over (partition by b.firm_id, b.key, b.txt order by b.rn)
  from base b where b.rn > 1;

  insert into home_drop(firm_id, slug, kind, item_key, table_name, row_id, keep_id)
  with lab as (select id, slug from firms f where f.deleted_at is null and public._lab_firm(f.id)),
  shared as (
    select l.id firm_id, public._checker_url_key(t.source_url) key, public._norm_txt(t.body) txt, t.id row_id
    from lab l join timeline_events t on t.firm_id = l.id
    where public._checker_url_key(t.source_url) is not null
      and exists (
        select 1 from press_item_firms pf join press_items p on p.id = pf.press_item_id
        where pf.firm_id = l.id and public._checker_url_key(p.url) = public._checker_url_key(t.source_url)
          and public._norm_txt(p.headline) = public._norm_txt(t.body))
  )
  select s.firm_id, l.slug, 'news', 'dup:time-press:' || s.row_id::text, 'timeline_events', s.row_id, null
  from shared s join lab l on l.id = s.firm_id
  where not exists (select 1 from home_drop d where d.row_id = s.row_id and d.table_name = 'timeline_events');

  insert into home_drop(firm_id, slug, kind, item_key, table_name, row_id, keep_id)
  with lab as (select id, slug from firms f where f.deleted_at is null and public._lab_firm(f.id)),
  base as (
    select l.id firm_id, l.slug, r.id row_id,
           row_number() over (partition by l.id, r.kind, r.stable_key, public._norm_txt(r.role)
             order by coalesce(r.hidden, false), r.id) rn
    from lab l join firm_people_roles r on r.firm_id = l.id
    where r.stable_key is not null
  )
  select firm_id, slug, 'people', 'dup:person:' || row_id::text, 'firm_people_roles', row_id,
         first_value(row_id) over (partition by firm_id, row_id order by rn)
  from base where rn > 1;

  insert into home_drop(firm_id, slug, kind, item_key, table_name, row_id, keep_id)
  with lab as (select id, slug from firms f where f.deleted_at is null and public._lab_firm(f.id)),
  base as (
    select l.id firm_id, l.slug, i.id row_id,
           row_number() over (partition by l.id, i.stable_key, public._norm_txt(i.title)
             order by coalesce(i.hidden, false), i.id) rn
    from lab l join firm_legal_items i on i.firm_id = l.id
    where i.stable_key is not null
  )
  select firm_id, slug, 'legal', 'dup:legal:' || row_id::text, 'firm_legal_items', row_id, null
  from base where rn > 1;

  insert into home_drop(firm_id, slug, kind, item_key, table_name, row_id, keep_id)
  with lab as (select id, slug from firms f where f.deleted_at is null and public._lab_firm(f.id)),
  base as (
    select l.id firm_id, l.slug, r.id row_id,
           first_value(r.id) over (partition by l.id, public._norm_txt(r.body), coalesce(r.source_urls[1], '')
             order by r.id) keep_id,
           row_number() over (partition by l.id, public._norm_txt(r.body), coalesce(r.source_urls[1], '')
             order by r.id) rn
    from lab l join reviews r on r.firm_id = l.id
    where coalesce(r.body, '') <> ''
  )
  select firm_id, slug, 'reviews', 'dup:review:' || row_id::text, 'reviews', row_id, keep_id
  from base where rn > 1;

  insert into home_drop(firm_id, slug, kind, item_key, table_name, row_id, keep_id)
  with lab as (select id, slug from firms f where f.deleted_at is null and public._lab_firm(f.id)),
  base as (
    select l.id firm_id, l.slug, u.dedupe_key, public._norm_txt(u.name) txt, u.id row_id,
           row_number() over (partition by l.id, u.dedupe_key, public._norm_txt(u.name) order by u.id) rn
    from lab l join funds u on u.firm_id = l.id
    where u.dedupe_key is not null
  ), one as (
    select firm_id, dedupe_key from base group by firm_id, dedupe_key having count(distinct txt) = 1
  )
  select b.firm_id, b.slug, 'funds', 'dup:fund:' || b.row_id::text, 'funds', b.row_id, null
  from base b join one o on o.firm_id = b.firm_id and o.dedupe_key = b.dedupe_key
  where b.rn > 1;

  insert into home_flag(firm_id, slug, kind, item_key, action, detail)
  with lab as (select id, slug from firms f where f.deleted_at is null and public._lab_firm(f.id)),
  news as (
    select l.id firm_id, l.slug, public._checker_url_key(p.url) key, public._norm_txt(p.headline) txt
    from lab l join press_item_firms pf on pf.firm_id = l.id join press_items p on p.id = pf.press_item_id
    where public._checker_url_key(p.url) is not null
    union all
    select l.id, l.slug, public._checker_url_key(t.source_url), public._norm_txt(t.body)
    from lab l join timeline_events t on t.firm_id = l.id
    where public._checker_url_key(t.source_url) is not null
  )
  select firm_id, slug, 'news', 'url:' || key, 'disagreement', jsonb_build_object('texts', count(distinct txt))
  from news group by firm_id, slug, key having count(distinct txt) > 1;

  insert into home_flag(firm_id, slug, kind, item_key, action, detail)
  with lab as (select id, slug from firms f where f.deleted_at is null and public._lab_firm(f.id))
  select l.id, l.slug, 'people', 'person:' || r.kind || ':' || r.stable_key, 'disagreement',
         jsonb_build_object('roles', count(distinct public._norm_txt(r.role)))
  from lab l join firm_people_roles r on r.firm_id = l.id
  where r.stable_key is not null
  group by l.id, l.slug, r.kind, r.stable_key
  having count(distinct public._norm_txt(r.role)) > 1;

  insert into home_flag(firm_id, slug, kind, item_key, action, detail)
  with lab as (select id, slug from firms f where f.deleted_at is null and public._lab_firm(f.id))
  select l.id, l.slug, 'legal', 'legal:' || i.stable_key, 'disagreement',
         jsonb_build_object('titles', count(distinct public._norm_txt(i.title)))
  from lab l join firm_legal_items i on i.firm_id = l.id
  where i.stable_key is not null
  group by l.id, l.slug, i.stable_key
  having count(distinct public._norm_txt(i.title)) > 1;

  insert into home_flag(firm_id, slug, kind, item_key, action, detail)
  with lab as (select id, slug from firms f where f.deleted_at is null and public._lab_firm(f.id))
  select l.id, l.slug, 'funds', 'fund:' || u.dedupe_key, 'disagreement',
         jsonb_build_object('names', count(distinct public._norm_txt(u.name)))
  from lab l join funds u on u.firm_id = l.id
  where u.dedupe_key is not null
  group by l.id, l.slug, u.dedupe_key
  having count(distinct public._norm_txt(u.name)) > 1;

  insert into home_flag(firm_id, slug, kind, item_key, action, detail)
  with lab as (select id, slug, legal_name from firms f where f.deleted_at is null and public._lab_firm(f.id))
  select l.id, l.slug, 'names', 'legal_name', 'merge', jsonb_build_object('alias', l.legal_name)
  from lab l
  where coalesce(btrim(l.legal_name), '') <> ''
    and not exists (
      select 1 from firm_aliases a where a.firm_id = l.id and lower(a.alias) = lower(l.legal_name));

  insert into home_flag(firm_id, slug, kind, item_key, action, detail)
  with lab as (select id, slug from firms f where f.deleted_at is null and public._lab_firm(f.id))
  select l.id, l.slug, 'funds', 'fact:' || f.id::text, 'merge', jsonb_build_object('value', left(f.value, 200))
  from lab l join firm_profile_facts f on f.firm_id = l.id and f.section = 'funds' and not coalesce(f.hidden, false)
  where exists (
    select 1 from funds u where u.firm_id = l.id
      and (u.dedupe_key = f.stable_key or public._norm_txt(u.name) = public._norm_txt(split_part(f.value, ' · ', 1))));

  insert into home_flag(firm_id, slug, kind, item_key, action, detail)
  with lab as (select id, slug from firms f where f.deleted_at is null and public._lab_firm(f.id))
  select l.id, l.slug, 'funds', 'held:' || f.id::text, 'held', jsonb_build_object('value', left(f.value, 200))
  from lab l join firm_profile_facts f on f.firm_id = l.id and f.section = 'funds' and not coalesce(f.hidden, false)
  where not exists (
    select 1 from funds u where u.firm_id = l.id
      and (u.dedupe_key = f.stable_key or public._norm_txt(u.name) = public._norm_txt(split_part(f.value, ' · ', 1))));

  insert into home_flag(firm_id, slug, kind, item_key, action, detail)
  with lab as (select id, slug from firms f where f.deleted_at is null and public._lab_firm(f.id))
  select l.id, l.slug, 'people',
         case when exists (
           select 1 from firm_people_roles r where r.firm_id = l.id and r.stable_key = public._person_key(p.full_name))
           then 'in:' else 'held:' end || fp.id::text,
         case when exists (
           select 1 from firm_people_roles r where r.firm_id = l.id and r.stable_key = public._person_key(p.full_name))
           then 'merge' else 'held' end,
         jsonb_build_object('name', p.full_name)
  from lab l
  join fund_people fp on fp.firm_id = l.id
  join people p on p.id = fp.person_id;

  insert into home_flag(firm_id, slug, kind, item_key, action, detail)
  with lab as (select id, slug from firms f where f.deleted_at is null and public._lab_firm(f.id))
  select l.id, l.slug, 'legal', 'held:reg:' || rr.id::text, 'held', jsonb_build_object('title', left(rr.title, 200))
  from lab l join regulatory_records rr on rr.firm_id = l.id
  where not exists (
    select 1 from firm_legal_items i where i.firm_id = l.id and public._norm_txt(i.title) = public._norm_txt(rr.title));

  insert into home_flag(firm_id, slug, kind, item_key, action, detail)
  with lab as (select id, slug from firms f where f.deleted_at is null and public._lab_firm(f.id))
  select l.id, l.slug, 'legal', 'held:matter:' || m.id::text, 'held', jsonb_build_object('title', left(m.title, 200))
  from lab l
  join legal_matter_firms mf on mf.firm_id = l.id
  join legal_matters m on m.id = mf.matter_id
  where not exists (
    select 1 from firm_legal_items i where i.firm_id = l.id and public._norm_txt(i.title) = public._norm_txt(m.title));

  insert into home_flag(firm_id, slug, kind, item_key, action, detail)
  with lab as (select id, slug, registry_id from firms f where f.deleted_at is null and public._lab_firm(f.id))
  select l.id, l.slug, 'lps', 'held:' || lp.id::text, 'held', jsonb_build_object('name', lp.lp_name)
  from lab l
  join bots.firm_lps lp on true
  join research_queue q on q.registry_id = lp.registry_id
  where l.registry_id = coalesce(public._registry_target(q.registry_id), q.registry_id)
    and lp.status = 'confirmed'
    and not exists (
      select 1 from firm_profile_facts x where x.firm_id = l.id and x.section = 'lps'
        and public._norm_txt(coalesce(x.label, x.value)) = public._norm_txt(lp.lp_name));

  insert into home_flag(firm_id, slug, kind, item_key, action, detail)
  select d.firm_id, d.slug, d.kind, d.item_key, 'duplicate', jsonb_build_object('table', d.table_name, 'row_id', d.row_id)
  from home_drop d;

  if p_write then
    update firm_aliases a set alias_type = case a.source
      when 'sec_legal' then 'legal' when 'previous_display' then 'old_name'
      when 'queue_name' then 'display' when 'merged' then 'old_name' else a.alias_type end
    where a.alias_type is null and public._lab_firm(a.firm_id);

    for r in select * from home_drop loop
      if r.table_name = 'press_item_firms' then
        insert into home_merge_backup(firm_id, table_name, item_key, row_data)
        select r.firm_id, 'press_item_firms', r.item_key, to_jsonb(pf)
        from press_item_firms pf where pf.press_item_id = r.row_id and pf.firm_id = r.firm_id;
        insert into home_merge_backup(firm_id, table_name, item_key, row_data)
        select r.firm_id, 'press_items', r.item_key || ':item', to_jsonb(p)
        from press_items p where p.id = r.row_id
          and not exists (select 1 from press_item_firms pf where pf.press_item_id = p.id and not (pf.firm_id = r.firm_id));
        delete from press_item_firms pf where pf.press_item_id = r.row_id and pf.firm_id = r.firm_id;
        delete from press_items p where p.id = r.row_id
          and not exists (select 1 from press_item_firms pf where pf.press_item_id = p.id);
      elsif r.table_name = 'timeline_events' then
        insert into home_merge_backup(firm_id, table_name, item_key, row_data)
        select r.firm_id, 'timeline_events', r.item_key, to_jsonb(t) from timeline_events t where t.id = r.row_id;
        delete from timeline_events t where t.id = r.row_id;
      elsif r.table_name = 'firm_people_roles' then
        insert into home_merge_backup(firm_id, table_name, item_key, row_data)
        select r.firm_id, 'firm_people_roles', r.item_key, to_jsonb(x) from firm_people_roles x where x.id = r.row_id;
        delete from firm_people_roles x where x.id = r.row_id;
      elsif r.table_name = 'firm_legal_items' then
        insert into home_merge_backup(firm_id, table_name, item_key, row_data)
        select r.firm_id, 'firm_legal_items', r.item_key, to_jsonb(x) from firm_legal_items x where x.id = r.row_id;
        delete from firm_legal_items x where x.id = r.row_id;
      elsif r.table_name = 'reviews' then
        update founder_accounts set moved_to_review = r.keep_id where moved_to_review = r.row_id and r.keep_id is not null;
        update founder_accounts set moved_to_review = null where moved_to_review = r.row_id and r.keep_id is null;
        insert into home_merge_backup(firm_id, table_name, item_key, row_data)
        select r.firm_id, 'reviews', r.item_key, to_jsonb(x) from reviews x where x.id = r.row_id;
        delete from reviews x where x.id = r.row_id;
      elsif r.table_name = 'funds' then
        insert into home_merge_backup(firm_id, table_name, item_key, row_data)
        select r.firm_id, 'funds', r.item_key, to_jsonb(x) from funds x where x.id = r.row_id;
        delete from funds x where x.id = r.row_id;
      end if;
    end loop;

    insert into firm_aliases(firm_id, alias, source, alias_type)
    select f.firm_id, f.detail->>'alias', 'sec_legal', 'legal'
    from home_flag f
    where f.action = 'merge' and f.kind = 'names'
      and not exists (
        select 1 from firm_aliases a where a.firm_id = f.firm_id and lower(a.alias) = lower(f.detail->>'alias'));

    with ins as (
      insert into home_merge_log(firm_id, kind, item_key, action, detail)
      select firm_id, kind, item_key, action, detail from home_flag
      on conflict (firm_id, kind, item_key, action) do nothing
      returning firm_id, kind, item_key, action, detail
    )
    insert into publish_checks(origin, bot_id, firm_id, section, kind, item, outcome, reason)
    select 'submission', 'checker', firm_id, kind, action,
           jsonb_build_object('item_key', item_key, 'detail', detail),
           case when action = 'disagreement' then 'conflict' when action = 'duplicate' then 'merged' else 'note' end,
           case when action = 'disagreement' then 'home merge: same item, values differ. Page row kept.'
                when action = 'duplicate' then 'home merge: exact copy removed.'
                when action = 'held' then 'home merge: side row stays off the page.'
                else 'home merge: already in the home. Sources kept.' end
    from ins
    where action in ('duplicate', 'disagreement', 'merge');
  end if;

  return query
  with kinds as (
    select * from (values ('news'),('people'),('legal'),('reviews'),('funds'),('deals'),('names'),('lps'),('aum'),('checks')) v(kind)
  ), firms as (
    select f.slug from firms f where f.deleted_at is null and public._lab_firm(f.id)
  ), agg as (
    select slug, kind,
           count(*) filter (where action = 'duplicate')::int duplicates,
           count(*) filter (where action = 'merge')::int merges,
           count(*) filter (where action = 'disagreement')::int disagreements,
           count(*) filter (where action = 'held')::int held
    from home_flag group by slug, kind
  )
  select fi.slug, k.kind,
         coalesce(a.duplicates, 0), coalesce(a.merges, 0), coalesce(a.disagreements, 0), coalesce(a.held, 0)
  from firms fi cross join kinds k
  left join agg a on a.slug = fi.slug and a.kind = k.kind
  where coalesce(a.duplicates, 0) + coalesce(a.merges, 0) + coalesce(a.disagreements, 0) + coalesce(a.held, 0) > 0
  order by fi.slug, k.kind;
end $$;
revoke all on function public.lab_one_home(boolean) from public, anon, authenticated;
