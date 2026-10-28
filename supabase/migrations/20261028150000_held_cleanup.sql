-- Cleanup of lab rows that had no home. Each one is backed up, then checked once.
-- A pass is moved into its home. A fail is deleted. Only the key, the kind, the firm,
-- and the reason stay on rejected_items, and the Checker will not add that key again.
-- The backup is home_held_backup. It is kept 3 days and is not deleted here.
-- This file installs the step. It does not change rows until lab_held_cleanup(true).
-- Rollback: supabase/rollbacks/20261028150000_held_cleanup.sql

create table if not exists public.rejected_items (
  id bigserial primary key,
  firm_id uuid not null references public.firms(id) on delete cascade,
  kind text not null,
  item_key text not null,
  reason text not null,
  created_at timestamptz not null default now(),
  unique (firm_id, kind, item_key)
);
alter table public.rejected_items enable row level security;
revoke all on public.rejected_items from public, anon, authenticated;
comment on table public.rejected_items is
  'Permanent. A lab item the Checker rejected. Holding and the Checker refuse the same key.';

create table if not exists public.home_held_backup (
  id bigserial primary key,
  backed_up_at timestamptz not null default now(),
  keep_until timestamptz not null default (now() + interval '3 days'),
  firm_id uuid,
  kind text not null,
  table_name text not null,
  item_key text not null,
  row_data jsonb not null,
  inserted_table text,
  inserted_id uuid,
  result text,
  reason text
);
alter table public.home_held_backup enable row level security;
revoke all on public.home_held_backup from public, anon, authenticated;
comment on table public.home_held_backup is
  'Full copy of each held lab row before it was moved or deleted. Keep 3 days. Do not delete without Alex OK.';

create or replace function public.lab_held_cleanup(p_write boolean default false)
returns table(slug text, kind text, passed int, failed int)
language plpgsql security definer set search_path = public, bots as $$
#variable_conflict use_column
declare r record; v_url text; v_out text; v_reason text; v_lvl smallint; v_name text; v_role text; v_key text;
  v_home uuid; v_inserted uuid; v_table text;
begin
  drop table if exists pg_temp.held_work;
  drop table if exists pg_temp.held_result;
  create temp table held_work (
    firm_id uuid, slug text, kind text, item_key text, src_table text, src_id text, detail jsonb
  ) on commit drop;
  create temp table held_result (
    slug text, kind text, outcome text, reason text
  ) on commit drop;

  insert into held_work(firm_id, slug, kind, item_key, src_table, src_id, detail)
  select g.firm_id, f.slug, g.kind, g.item_key,
    case
      when g.kind = 'funds' then 'firm_profile_facts'
      when g.kind = 'people' then 'fund_people'
      when g.item_key like 'held:reg:%' then 'regulatory_records'
      when g.item_key like 'held:matter:%' then 'legal_matter_firms'
      else 'firm_lps'
    end,
    case
      when g.item_key like 'held:reg:%' then substring(g.item_key from 10)
      when g.item_key like 'held:matter:%' then substring(g.item_key from 13)
      else substring(g.item_key from 6)
    end,
    g.detail
  from home_merge_log g
  join firms f on f.id = g.firm_id
  where g.action = 'held' and public._lab_firm(g.firm_id);

  for r in select * from held_work loop
    v_url := null; v_out := null; v_reason := null; v_lvl := null; v_name := null; v_role := null; v_home := null; v_inserted := null; v_table := null;
    if r.src_table = 'firm_profile_facts' then
      select (select s.url from fact_sources fs join sources s on s.id = fs.source_id
               where fs.fact_type = 'firm_profile_facts' and fs.fact_id = x.id and s.url ~* '^https?://'
               order by fs.sort_order limit 1),
             left(coalesce(nullif(btrim(x.label), ''), split_part(x.value, ' · ', 1), 'Fund'), 300)
        into v_url, v_name
      from firm_profile_facts x where x.id = r.src_id::uuid;
    elsif r.src_table = 'fund_people' then
      select left(p.full_name, 120), nullif(btrim(fp.role), '')
        into v_name, v_role
      from fund_people fp join people p on p.id = fp.person_id
      where fp.id = r.src_id::uuid;
      v_url := null;
    elsif r.src_table = 'regulatory_records' then
      select left(x.title, 300), case when x.evidence_key ~* '^https?://' then x.evidence_key end
        into v_name, v_url
      from regulatory_records x where x.id = r.src_id::uuid;
    elsif r.src_table = 'legal_matter_firms' then
      select left(m.title, 300), null
        into v_name, v_url
      from legal_matter_firms mf join legal_matters m on m.id = mf.matter_id
      where mf.id = r.src_id::uuid;
    else
      select left(lp.lp_name, 200), case when lp.source_url ~* '^https?://' then lp.source_url end
        into v_name, v_url
      from firm_lps lp where lp.id::text = r.src_id;
    end if;

    if r.src_table = 'firm_profile_facts' and not exists (select 1 from firm_profile_facts where id = r.src_id::uuid) then continue; end if;
    if r.src_table = 'fund_people' and not exists (select 1 from fund_people where id = r.src_id::uuid) then continue; end if;
    if r.src_table = 'regulatory_records' and not exists (select 1 from regulatory_records where id = r.src_id::uuid) then continue; end if;
    if r.src_table = 'legal_matter_firms' and not exists (select 1 from legal_matter_firms where id = r.src_id::uuid) then continue; end if;
    if r.src_table = 'firm_lps' and not exists (select 1 from firm_lps where id::text = r.src_id) then continue; end if;

    if v_url is null then
      v_out := 'failure'; v_reason := 'link is not real (missing, not http, or a search/chat page)';
    else
      select d.outcome, d.reason, d.lvl into v_out, v_reason, v_lvl
      from public._checker_decide(r.firm_id,
        case r.kind when 'funds' then 'funds' when 'people' then 'people' when 'legal' then 'legal' else 'lps' end,
        jsonb_build_object('name', v_name, 'label', v_name, 'title', v_name, 'value', coalesce(r.detail->>'value', v_name)),
        v_url, null, null) d;
    end if;
    v_key := coalesce(public._checker_url_key(v_url), 'id:' || r.src_id);
    if coalesce(public._norm_txt(v_name), '') <> '' then
      v_key := coalesce(public._checker_url_key(v_url), 'name:' || public._norm_txt(v_name));
    end if;

    insert into held_result(slug, kind, outcome, reason) values (r.slug, r.kind, v_out, coalesce(v_reason, v_out));

    if p_write and v_out = 'published' then
      if r.src_table = 'firm_profile_facts' then
        insert into home_held_backup(firm_id, kind, table_name, item_key, row_data, result, reason)
        select r.firm_id, r.kind, 'firm_profile_facts', v_key, jsonb_build_object('row', to_jsonb(x), 'url', v_url), 'passed', v_reason
        from firm_profile_facts x where x.id = r.src_id::uuid;
        select u.id into v_home from funds u
         where u.firm_id = r.firm_id and u.dedupe_key = public._fund_key(v_name) and public._fund_key(v_name) is not null
         limit 1;
        if v_home is null then
          insert into funds(firm_id, name, sort_order, data_status, source_system, source_urls, filing_url, dedupe_key)
          values (r.firm_id, v_name, 900, 'real', 'checker',
                  case when v_url is null then '{}'::text[] else array[v_url] end,
                  case when v_url ~* 'sec.gov|adviserinfo' then v_url end,
                  public._fund_key(v_name))
          returning id into v_inserted;
          update home_held_backup set inserted_table = 'funds', inserted_id = v_inserted
           where id = (select max(id) from home_held_backup where firm_id = r.firm_id and item_key = v_key);
        else
          update funds set source_urls = (
            select array(select distinct u from unnest(coalesce(source_urls, '{}'::text[]) || case when v_url is null then '{}'::text[] else array[v_url] end) u)
          ) where id = v_home;
        end if;
        delete from fact_sources where fact_type = 'firm_profile_facts' and fact_id = r.src_id::uuid;
        delete from firm_profile_facts where id = r.src_id::uuid;
      elsif r.src_table = 'fund_people' then
        insert into home_held_backup(firm_id, kind, table_name, item_key, row_data, result, reason)
        select r.firm_id, r.kind, 'fund_people', v_key, jsonb_build_object('row', to_jsonb(fp), 'url', v_url), 'passed', v_reason
        from fund_people fp where fp.id = r.src_id::uuid;
        insert into firm_people_roles(firm_id, kind, person_name, role, sort_order, checked_on, checked_by, source_level)
        values (r.firm_id, case when coalesce(v_role, '') ~* 'board' then 'board' else 'officer' end,
                left(v_name, 120), left(coalesce(v_role, 'Role not stated'), 300), 900, now(), 'Checker', v_lvl)
        returning id into v_inserted;
        update home_held_backup set inserted_table = 'firm_people_roles', inserted_id = v_inserted
         where id = (select max(id) from home_held_backup where firm_id = r.firm_id and item_key = v_key);
        delete from fund_people where id = r.src_id::uuid;
      elsif r.src_table = 'regulatory_records' then
        insert into home_held_backup(firm_id, kind, table_name, item_key, row_data, result, reason)
        select r.firm_id, r.kind, 'regulatory_records', v_key, jsonb_build_object('row', to_jsonb(x), 'url', v_url), 'passed', v_reason
        from regulatory_records x where x.id = r.src_id::uuid;
        insert into firm_legal_items(firm_id, grp, title, sort_order, checked_on, checked_by, source_level)
        values (r.firm_id, 'regulator', left(v_name, 300), 900, now(), 'Checker', v_lvl)
        returning id into v_inserted;
        update home_held_backup set inserted_table = 'firm_legal_items', inserted_id = v_inserted
         where id = (select max(id) from home_held_backup where firm_id = r.firm_id and item_key = v_key);
        delete from regulatory_records where id = r.src_id::uuid;
      elsif r.src_table = 'legal_matter_firms' then
        insert into home_held_backup(firm_id, kind, table_name, item_key, row_data, result, reason)
        select r.firm_id, r.kind, 'legal_matter_firms', v_key, jsonb_build_object('row', to_jsonb(mf), 'url', v_url), 'passed', v_reason
        from legal_matter_firms mf where mf.id = r.src_id::uuid;
        insert into firm_legal_items(firm_id, grp, title, sort_order, checked_on, checked_by, source_level)
        values (r.firm_id, 'case', left(v_name, 300), 900, now(), 'Checker', v_lvl)
        returning id into v_inserted;
        update home_held_backup set inserted_table = 'firm_legal_items', inserted_id = v_inserted
         where id = (select max(id) from home_held_backup where firm_id = r.firm_id and item_key = v_key);
        delete from legal_matter_firms where id = r.src_id::uuid;
      else
        insert into home_held_backup(firm_id, kind, table_name, item_key, row_data, result, reason)
        select r.firm_id, r.kind, 'firm_lps', v_key, jsonb_build_object('row', to_jsonb(lp), 'url', v_url), 'passed', v_reason
        from firm_lps lp where lp.id::text = r.src_id;
        insert into firm_profile_facts(firm_id, section, label, value, sort_order, origin, checked_on, checked_by, source_level)
        values (r.firm_id, 'lps', left(v_name, 200), left(coalesce(r.detail->>'name', v_name), 400), 900, 'checker', now(), 'Checker', v_lvl)
        returning id into v_inserted;
        update home_held_backup set inserted_table = 'firm_profile_facts', inserted_id = v_inserted
         where id = (select max(id) from home_held_backup where firm_id = r.firm_id and item_key = v_key);
        delete from firm_lps where id::text = r.src_id;
      end if;
    elsif p_write then
      if r.src_table = 'firm_profile_facts' then
        insert into home_held_backup(firm_id, kind, table_name, item_key, row_data, result, reason)
        select r.firm_id, r.kind, 'firm_profile_facts', v_key, jsonb_build_object('row', to_jsonb(x), 'url', v_url), 'failed', v_reason from firm_profile_facts x where x.id = r.src_id::uuid;
        delete from fact_sources where fact_type = 'firm_profile_facts' and fact_id = r.src_id::uuid;
        delete from firm_profile_facts where id = r.src_id::uuid;
      elsif r.src_table = 'fund_people' then
        insert into home_held_backup(firm_id, kind, table_name, item_key, row_data, result, reason)
        select r.firm_id, r.kind, 'fund_people', v_key, jsonb_build_object('row', to_jsonb(fp), 'url', v_url), 'failed', v_reason from fund_people fp where fp.id = r.src_id::uuid;
        delete from fund_people where id = r.src_id::uuid;
      elsif r.src_table = 'regulatory_records' then
        insert into home_held_backup(firm_id, kind, table_name, item_key, row_data, result, reason)
        select r.firm_id, r.kind, 'regulatory_records', v_key, jsonb_build_object('row', to_jsonb(x), 'url', v_url), 'failed', v_reason from regulatory_records x where x.id = r.src_id::uuid;
        delete from regulatory_records where id = r.src_id::uuid;
      elsif r.src_table = 'legal_matter_firms' then
        insert into home_held_backup(firm_id, kind, table_name, item_key, row_data, result, reason)
        select r.firm_id, r.kind, 'legal_matter_firms', v_key, jsonb_build_object('row', to_jsonb(mf), 'url', v_url), 'failed', v_reason from legal_matter_firms mf where mf.id = r.src_id::uuid;
        delete from legal_matter_firms where id = r.src_id::uuid;
      else
        insert into home_held_backup(firm_id, kind, table_name, item_key, row_data, result, reason)
        select r.firm_id, r.kind, 'firm_lps', v_key, jsonb_build_object('row', to_jsonb(lp), 'url', v_url), 'failed', v_reason from firm_lps lp where lp.id::text = r.src_id;
        delete from firm_lps where id::text = r.src_id;
      end if;
      insert into rejected_items(firm_id, kind, item_key, reason)
      values (r.firm_id, r.kind, v_key, coalesce(v_reason, 'failed'))
      on conflict (firm_id, kind, item_key) do nothing;
      if coalesce(public._norm_txt(v_name), '') <> '' and v_key <> 'name:' || public._norm_txt(v_name) then
        insert into rejected_items(firm_id, kind, item_key, reason)
        values (r.firm_id, r.kind, 'name:' || public._norm_txt(v_name), coalesce(v_reason, 'failed'))
        on conflict (firm_id, kind, item_key) do nothing;
      end if;
    end if;
  end loop;

  return query
  select r.slug, r.kind,
         count(*) filter (where r.outcome = 'published')::int,
         count(*) filter (where r.outcome is distinct from 'published')::int
  from held_result r
  group by r.slug, r.kind
  order by r.slug, r.kind;
end $$;
revoke all on function public.lab_held_cleanup(boolean) from public, anon, authenticated;
create or replace function public._checker_decide(
  p_firm uuid, p_section text, p_f jsonb, p_url text, p_check int, p_probes jsonb)
returns table(lvl smallint, outcome text, reason text)
language plpgsql stable security definer set search_path = public as $$
declare base smallint; blob text; who text; host text; firm_dom text; company_key text;
begin
  if exists (
    select 1 from rejected_items r
    where r.firm_id = p_firm and (
      (coalesce(public._checker_url_key(p_url), '') <> '' and r.item_key = public._checker_url_key(p_url))
      or (coalesce(public._norm_txt(coalesce(p_f->>'name', p_f->>'label', p_f->>'title', '')), '') <> ''
          and r.item_key = 'name:' || public._norm_txt(coalesce(p_f->>'name', p_f->>'label', p_f->>'title', '')))
    )
  ) then
    lvl := null; outcome := 'failure'; reason := 'rejected earlier; not added again';
    return next; return;
  end if;
  if public.source_tier(p_url) is null then
    lvl := null; outcome := 'failure'; reason := 'link is not real (missing, not http, or a search/chat page)';
    return next; return;
  end if;
  if p_probes is not null and (p_probes ? p_url) and (p_probes->>p_url) in ('false', 'f') then
    lvl := null; outcome := 'failure'; reason := 'dead link';
    return next; return;
  end if;
  if p_check is not null and p_url ~* 'opensanctions\.org' and p_check not in (1, 2, 10) then
    lvl := null; outcome := 'failure'; reason := 'OpenSanctions is only a source inside checks 1, 2 and 10';
    return next; return;
  end if;
  base := public._source_level(p_url, p_firm, p_check);
  blob := concat_ws(' ', p_f->>'headline', p_f->>'snippet', p_f->>'event', p_f->>'quote', p_f->>'title', p_f->>'value', p_f->>'name', p_f->>'who');
  who := lower(btrim(coalesce(p_f->>'who', p_f->>'author', '')));
  host := public._dom(p_url);
  select nullif(lower(primary_domain), '') into firm_dom from firms where id = p_firm;

  if p_section = 'legal' or public._court_register(p_url) then
    if public._court_register(p_url) or base = 1 then
      lvl := 1; outcome := 'published'; reason := null;
    else
      lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: lawsuit source is not CourtListener, PACER, or uscourts.gov';
    end if;
    return next; return;
  end if;

  if p_section = 'founders' then
    if who in ('', 'anonymous', 'anon', 'unknown')
       and coalesce(p_f->>'quote', '') !~* 'founder|i founded'
       and coalesce(p_f->>'type', '') !~* 'founder' then
      lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: anonymous, no founder claim';
      return next; return;
    end if;
    if not (public._host_is(p_url, 'reddit.com') or public._host_is(p_url, 'x.com')
            or public._host_is(p_url, 'twitter.com') or public._host_is(p_url, 'linkedin.com')) then
      lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: review is not from Reddit, X, or LinkedIn';
      return next; return;
    end if;
    if coalesce(btrim(p_f->>'quote'), '') = '' then
      lvl := null; outcome := 'failure'; reason := 'review is not copied word for word';
      return next; return;
    end if;
    if not public._names_firm(p_firm, blob) then
      lvl := null; outcome := 'failure'; reason := 'off-topic: review does not name the firm';
      return next; return;
    end if;
    if who !~* 'founder' and coalesce(p_f->>'quote', '') !~* 'founder|i founded'
       and coalesce(p_f->>'type', '') !~* 'founder' then
      lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: writer does not say they are a founder';
      return next; return;
    end if;
    lvl := 2; outcome := 'published'; reason := null;
    return next; return;
  end if;

  if p_section in ('press', 'timeline') then
    if public._known_outlet(p_url) then
      if public._names_firm(p_firm, blob) then
        lvl := 2; outcome := 'published'; reason := null;
      else
        lvl := null; outcome := 'failure'; reason := 'off-topic: story does not name the firm';
      end if;
    else
      lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: unknown outlet, not shown';
    end if;
    return next; return;
  end if;

  if p_section = 'people' then
    if public._host_is(p_url, 'sec.gov') or public._host_is(p_url, 'adviserinfo.sec.gov') then
      lvl := 1; outcome := 'published'; reason := null;
    elsif firm_dom is not null and (host = firm_dom or host like '%.' || firm_dom) then
      lvl := 2; outcome := 'published'; reason := null;
    elsif public._host_is(p_url, 'linkedin.com') and p_url ~* '/in/' then
      lvl := 2; outcome := 'published'; reason := null;
    else
      lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: people source is not Form ADV, the team page, or that person''s LinkedIn history';
    end if;
    return next; return;
  end if;

  if p_section = 'deals' then
    if public._host_is(p_url, 'sec.gov') then
      lvl := 2; outcome := 'published'; reason := null;
    elsif public._known_outlet(p_url) then
      if public._names_firm(p_firm, blob) then
        lvl := 2; outcome := 'published'; reason := null;
      else
        lvl := null; outcome := 'failure'; reason := 'off-topic: deal story does not name the firm';
      end if;
    else
      company_key := lower(regexp_replace(coalesce(p_f->>'company', ''), '[^a-zA-Z0-9]', '', 'g'));
      if length(company_key) >= 3 and position(company_key in lower(regexp_replace(coalesce(host, ''), '[^a-zA-Z0-9]', '', 'g'))) > 0
         and (firm_dom is null or (host <> firm_dom and host not like '%.' || firm_dom)) then
        lvl := 2; outcome := 'published'; reason := null;
      else
        lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: deal source is not a company press release, Form D, or a known outlet';
      end if;
    end if;
    return next; return;
  end if;

  if p_section = 'social' then
    if firm_dom is not null and (host = firm_dom or host like '%.' || firm_dom) then
      lvl := 2; outcome := 'published'; reason := null;
    else
      lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: social count is not from an account linked on the firm site';
    end if;
    return next; return;
  end if;

  if p_section in ('portfolio', 'sectors') then
    if coalesce(p_f->>'domain', '') <> '' and public._host_is(p_url, p_f->>'domain') then
      lvl := 2; outcome := 'published'; reason := null;
    else
      company_key := lower(regexp_replace(coalesce(p_f->>'company', ''), '[^a-zA-Z0-9]', '', 'g'));
      if length(company_key) >= 3 and position(company_key in lower(regexp_replace(coalesce(host, ''), '[^a-zA-Z0-9]', '', 'g'))) > 0 then
        lvl := 2; outcome := 'published'; reason := null;
      else
        lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: portfolio source is not the company''s own site';
      end if;
    end if;
    return next; return;
  end if;

  if base in (1, 2) then
    lvl := base; outcome := 'published'; reason := null;
  elsif base is null then
    lvl := null; outcome := 'failure'; reason := 'link is not real (missing, not http, or a search/chat page)';
  else
    lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: elsewhere online, not shown';
  end if;
  return next;
end $$;

revoke all on function public._checker_decide(uuid, text, jsonb, text, int, jsonb) from public, anon, authenticated;
