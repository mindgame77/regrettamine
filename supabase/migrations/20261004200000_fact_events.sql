-- One row per fact added to the database. The landing header shows the count.
-- Readable by signed-out visitors as a count only. The rows themselves are not.

create table public.fact_events (
  id uuid primary key default gen_random_uuid(),
  table_name text not null,
  row_id uuid not null,
  created_at timestamptz not null default now(),
  unique (table_name, row_id)
);

create index fact_events_created_idx on public.fact_events (created_at desc);

alter table public.fact_events enable row level security;

create or replace function public.record_fact_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.fact_events (table_name, row_id, created_at)
  values (tg_table_name, new.id, coalesce(new.created_at, now()))
  on conflict (table_name, row_id) do nothing;
  return new;
end;
$$;

-- A review counts once it is public. The app stores that as moderation_status
-- 'approved' (and accepts 'published' if a row is inserted that way). Pending
-- inserts do not count; becoming approved later does.
create or replace function public.record_published_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.moderation_status in ('approved', 'published')
     and (tg_op = 'INSERT' or old.moderation_status is distinct from new.moderation_status) then
    insert into public.fact_events (table_name, row_id, created_at)
    values ('reviews', new.id, coalesce(new.created_at, now()))
    on conflict (table_name, row_id) do nothing;
  end if;
  return new;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array[
    'firms', 'funds', 'people', 'fund_people', 'legal_matters', 'sources', 'score_results', 'site_updates'
  ]
  loop
    execute format(
      'create trigger %I after insert on public.%I for each row execute function public.record_fact_event()',
      t || '_fact_event', t
    );
  end loop;
end $$;

create trigger reviews_fact_event
  after insert or update of moderation_status on public.reviews
  for each row execute function public.record_published_review();

insert into public.fact_events (table_name, row_id, created_at)
select 'firms', id, created_at from public.firms
on conflict (table_name, row_id) do nothing;

insert into public.fact_events (table_name, row_id, created_at)
select 'funds', id, created_at from public.funds
on conflict (table_name, row_id) do nothing;

insert into public.fact_events (table_name, row_id, created_at)
select 'people', id, created_at from public.people
on conflict (table_name, row_id) do nothing;

insert into public.fact_events (table_name, row_id, created_at)
select 'fund_people', id, created_at from public.fund_people
on conflict (table_name, row_id) do nothing;

insert into public.fact_events (table_name, row_id, created_at)
select 'legal_matters', id, created_at from public.legal_matters
on conflict (table_name, row_id) do nothing;

insert into public.fact_events (table_name, row_id, created_at)
select 'sources', id, created_at from public.sources
on conflict (table_name, row_id) do nothing;

insert into public.fact_events (table_name, row_id, created_at)
select 'score_results', id, created_at from public.score_results
on conflict (table_name, row_id) do nothing;

insert into public.fact_events (table_name, row_id, created_at)
select 'reviews', id, created_at from public.reviews
where moderation_status in ('approved', 'published')
on conflict (table_name, row_id) do nothing;

insert into public.fact_events (table_name, row_id, created_at)
select 'site_updates', id, created_at from public.site_updates
on conflict (table_name, row_id) do nothing;

create or replace function public.fact_record_count()
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select count(*) from public.fact_events;
$$;

revoke all on function public.fact_record_count() from public;
grant execute on function public.fact_record_count() to anon, authenticated, service_role;

-- Full landing list for a signed-in user. Signed-out callers cannot execute it.
create or replace function public.landing_funds()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return '[]'::jsonb;
  end if;
  return coalesce((
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'id', slug,
      'name', name,
      'ini', initials,
      'short', short_name,
      'hq', hq,
      'metro', metro,
      'since', founded_year,
      'type', firm_type,
      'aum', aum_billions,
      'aumAsOf', aum_as_of,
      'aumStale', aum_stale,
      'aumSrc', aum_source,
      'score', list_score,
      'v2', list_v2,
      'band', list_band,
      'legal', list_legal_active,
      'legalNote', legal_note,
      'updated', to_char(updated_on, 'YYYY-MM-DD'),
      'updatedTs', updated_ts,
      'updatedS', updated_label,
      'old', list_previous_score,
      'lo', list_range_low,
      'hi', list_range_high,
      'cov', list_coverage,
      'verdict', list_verdict,
      'report', report_slug
    )) order by list_score desc nulls last, name)
    from public.firms
    where published and not is_test
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.landing_funds() from public;
grant execute on function public.landing_funds() to authenticated, service_role;
