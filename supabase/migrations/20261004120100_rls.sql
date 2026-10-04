-- Public read of published firms. Writes only for authenticated admins.
-- Local Postgres gets the Supabase roles if they are missing. On Supabase they already exist.

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end $$;

grant usage on schema public to anon, authenticated, service_role;

create or replace function public.firm_is_public(fid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from firms f
    where f.id = fid and f.published and not f.is_test
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select p.is_admin from profiles p where p.id = auth.uid()),
    false
  );
$$;

revoke all on function public.firm_is_public(uuid) from public;
revoke all on function public.is_admin() from public;
grant execute on function public.firm_is_public(uuid) to anon, authenticated, service_role;
grant execute on function public.is_admin() to anon, authenticated, service_role;
grant execute on function public.published_site_bundle() to anon, authenticated, service_role;

-- Helper: enable RLS and add the two standard policies for a table that has firm_id.
-- Tables without firm_id get custom policies below.

do $$
declare t text;
begin
  for t in
    select tablename from pg_tables where schemaname = 'public'
  loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- firms: the public predicate is on the row itself.
create policy firms_public_read on public.firms
  for select to anon, authenticated
  using (published and not is_test);

create policy firms_admin_write on public.firms
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Child tables keyed by firm_id.
do $$
declare t text;
begin
  foreach t in array array[
    'funds', 'fund_entities', 'fund_people', 'investments', 'reviews',
    'legal_matter_firms', 'regulatory_records', 'sanctions_checks',
    'fact_sources', 'takeaways', 'ask_questions', 'copy_blocks', 'page_chips',
    'firm_meta_items', 'list_items', 'portfolio_metrics', 'firm_ranks',
    'evidence_cards', 'score_results'
  ]
  loop
    execute format(
      'create policy %I on public.%I for select to anon, authenticated using (public.firm_is_public(firm_id))',
      t || '_public_read', t
    );
    execute format(
      'create policy %I on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())',
      t || '_admin_write', t
    );
  end loop;
end $$;

-- press_item_firms uses firm_id but its primary key is composite. Same predicate.
create policy press_item_firms_public_read on public.press_item_firms
  for select to anon, authenticated
  using (public.firm_is_public(firm_id));
create policy press_item_firms_admin_write on public.press_item_firms
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Shared dimensions: visible when a public firm points at them.

create policy people_public_read on public.people
  for select to anon, authenticated
  using (
    exists (select 1 from fund_people fp where fp.person_id = people.id and public.firm_is_public(fp.firm_id))
    or exists (select 1 from reviews r where public.firm_is_public(r.firm_id) and (r.founder_person_id = people.id or r.partner_person_id = people.id))
    or exists (select 1 from investments i where i.board_person_id = people.id and public.firm_is_public(i.firm_id))
    or exists (
      select 1 from company_founders cf
      join investments i on i.company_id = cf.company_id
      where cf.person_id = people.id and public.firm_is_public(i.firm_id)
    )
  );
create policy people_admin_write on public.people
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy portfolio_companies_public_read on public.portfolio_companies
  for select to anon, authenticated
  using (exists (
    select 1 from investments i
    where i.company_id = portfolio_companies.id and public.firm_is_public(i.firm_id)
  ));
create policy portfolio_companies_admin_write on public.portfolio_companies
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy company_founders_public_read on public.company_founders
  for select to anon, authenticated
  using (exists (
    select 1 from investments i
    where i.company_id = company_founders.company_id and public.firm_is_public(i.firm_id)
  ));
create policy company_founders_admin_write on public.company_founders
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy review_ratings_public_read on public.review_ratings
  for select to anon, authenticated
  using (exists (
    select 1 from reviews r
    where r.id = review_ratings.review_id and public.firm_is_public(r.firm_id)
  ));
create policy review_ratings_admin_write on public.review_ratings
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy legal_matters_public_read on public.legal_matters
  for select to anon, authenticated
  using (exists (
    select 1 from legal_matter_firms l
    where l.matter_id = legal_matters.id and public.firm_is_public(l.firm_id)
  ));
create policy legal_matters_admin_write on public.legal_matters
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy legal_matter_parties_public_read on public.legal_matter_parties
  for select to anon, authenticated
  using (exists (
    select 1 from legal_matter_firms l
    where l.matter_id = legal_matter_parties.matter_id and public.firm_is_public(l.firm_id)
  ));
create policy legal_matter_parties_admin_write on public.legal_matter_parties
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy filings_public_read on public.filings
  for select to anon, authenticated
  using (exists (
    select 1 from legal_matter_firms l
    where l.matter_id = filings.matter_id and public.firm_is_public(l.firm_id)
  ));
create policy filings_admin_write on public.filings
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy docket_entries_public_read on public.docket_entries
  for select to anon, authenticated
  using (exists (
    select 1 from legal_matter_firms l
    where l.matter_id = docket_entries.matter_id and public.firm_is_public(l.firm_id)
  ));
create policy docket_entries_admin_write on public.docket_entries
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy legal_groups_public_read on public.legal_groups
  for select to anon, authenticated
  using (public.firm_is_public(firm_id));
create policy legal_groups_admin_write on public.legal_groups
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy legal_group_items_public_read on public.legal_group_items
  for select to anon, authenticated
  using (exists (
    select 1 from legal_groups g
    where g.id = legal_group_items.group_id and public.firm_is_public(g.firm_id)
  ));
create policy legal_group_items_admin_write on public.legal_group_items
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy press_items_public_read on public.press_items
  for select to anon, authenticated
  using (exists (
    select 1 from press_item_firms p
    where p.press_item_id = press_items.id and public.firm_is_public(p.firm_id)
  ));
create policy press_items_admin_write on public.press_items
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy sources_public_read on public.sources
  for select to anon, authenticated
  using (exists (
    select 1 from fact_sources fs
    where fs.source_id = sources.id and public.firm_is_public(fs.firm_id)
  ));
create policy sources_admin_write on public.sources
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy evidence_lines_public_read on public.evidence_lines
  for select to anon, authenticated
  using (exists (
    select 1 from evidence_cards c
    where c.id = evidence_lines.card_id and public.firm_is_public(c.firm_id)
  ));
create policy evidence_lines_admin_write on public.evidence_lines
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy score_result_parts_public_read on public.score_result_parts
  for select to anon, authenticated
  using (exists (
    select 1 from score_results r
    where r.id = score_result_parts.result_id and public.firm_is_public(r.firm_id)
  ));
create policy score_result_parts_admin_write on public.score_result_parts
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy score_lines_public_read on public.score_lines
  for select to anon, authenticated
  using (exists (
    select 1 from score_results r
    where r.id = score_lines.result_id and public.firm_is_public(r.firm_id)
  ));
create policy score_lines_admin_write on public.score_lines
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy score_inputs_public_read on public.score_inputs
  for select to anon, authenticated
  using (exists (
    select 1 from score_results r
    where r.id = score_inputs.result_id and public.firm_is_public(r.firm_id)
  ));
create policy score_inputs_admin_write on public.score_inputs
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Methodology and the gating limits are readable. Writes are admin-only.
create policy score_versions_public_read on public.score_versions
  for select to anon, authenticated using (true);
create policy score_versions_admin_write on public.score_versions
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy score_sections_public_read on public.score_sections
  for select to anon, authenticated using (true);
create policy score_sections_admin_write on public.score_sections
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy site_stats_public_read on public.site_stats
  for select to anon, authenticated using (true);
create policy site_stats_admin_write on public.site_stats
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Homepage updates are public. A row may name one firm or none ("all funds").
create policy site_updates_public_read on public.site_updates
  for select to anon, authenticated
  using (firm_id is null or public.firm_is_public(firm_id));
create policy site_updates_admin_write on public.site_updates
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy gating_policies_public_read on public.gating_policies
  for select to anon, authenticated using (true);
create policy gating_policies_admin_write on public.gating_policies
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Profiles: a person reads their own row. Admins read and write every row.
-- is_admin cannot be flipped by the owner of the row (the WITH CHECK keeps their current flag).
create policy profiles_select on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_admin());

create policy profiles_insert on public.profiles
  for insert to authenticated
  with check (id = auth.uid() and is_admin = false);

create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid() and not public.is_admin())
  with check (id = auth.uid() and is_admin = false);

create policy profiles_admin_write on public.profiles
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Report views: the account ledger. A user reads and writes only their own rows.
create policy report_views_select on public.report_views
  for select to authenticated
  using (profile_id = auth.uid() or public.is_admin());

create policy report_views_insert on public.report_views
  for insert to authenticated
  with check (profile_id = auth.uid() or public.is_admin());

create policy report_views_update on public.report_views
  for update to authenticated
  using (profile_id = auth.uid() or public.is_admin())
  with check (profile_id = auth.uid() or public.is_admin());

create policy report_views_admin_delete on public.report_views
  for delete to authenticated
  using (public.is_admin());

grant select on all tables in schema public to anon, authenticated;
grant insert, update, delete on all tables in schema public to authenticated;
grant all on all tables in schema public to service_role;

alter default privileges in schema public grant select on tables to anon, authenticated;
alter default privileges in schema public grant insert, update, delete on tables to authenticated;
alter default privileges in schema public grant all on tables to service_role;
