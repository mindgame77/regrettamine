-- Share-experience reviews. Ratings and the LinkedIn check live on the review.
-- linkedin_url is verification-only: anon and authenticated cannot select it,
-- and the public bundle does not include it.
-- first_hand and verification_status stay at the server defaults for those roles.

alter table public.reviews
  add column connection_type text,
  add column linkedin_url text,
  add column honesty smallint,
  add column support_after_check smallint,
  add column founder_friendly_terms smallint,
  add column responsiveness smallint,
  add column hard_times smallint;

alter table public.reviews
  drop constraint if exists reviews_connection_type_check;

alter table public.reviews
  add constraint reviews_connection_type_check
  check (connection_type is null or connection_type in (
    'founder_ceo', 'co_founder', 'executive', 'employee', 'pitched', 'co_investor'
  ));

alter table public.reviews
  drop constraint if exists reviews_linkedin_url_check;

alter table public.reviews
  add constraint reviews_linkedin_url_check
  check (
    linkedin_url is null
    or linkedin_url ~* '^(https?://)?((www|[a-z]{2})\.)?linkedin\.com/in/[A-Za-z0-9\-_%]+/?$'
  );

alter table public.reviews
  drop constraint if exists reviews_rating_range_check;

alter table public.reviews
  add constraint reviews_rating_range_check
  check (
    (honesty is null or honesty between 1 and 5)
    and (support_after_check is null or support_after_check between 1 and 5)
    and (founder_friendly_terms is null or founder_friendly_terms between 1 and 5)
    and (responsiveness is null or responsiveness between 1 and 5)
    and (hard_times is null or hard_times between 1 and 5)
  );

create or replace function public.protect_review_server_fields()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- Signed-in visitors cannot mark a review first-hand or verified.
  -- A moderator (table owner or service role) sets those later.
  if current_user in ('anon', 'authenticated') then
    new.first_hand := false;
    new.verification_status := 'unverified';
  end if;
  return new;
end;
$$;

drop trigger if exists reviews_protect_server_fields on public.reviews;
create trigger reviews_protect_server_fields
  before insert or update on public.reviews
  for each row execute function public.protect_review_server_fields();

revoke all on function public.protect_review_server_fields() from public;
grant execute on function public.protect_review_server_fields() to anon, authenticated, service_role;

-- Table-level grants cover every column, so a column revoke would not stick.
-- Re-grant the columns a visitor may touch. first_hand and verification_status
-- are missing on purpose, and linkedin_url is missing from select.
revoke select, insert, update, delete on public.reviews from anon, authenticated;

grant select (
  id, firm_id, fund_id, company_id, founder_person_id, partner_person_id,
  body, first_hand, verification_status, moderation_status, reviewed_on,
  created_at, updated_at, profile_id, anonymous, role_label, round_label,
  would_again, verification_method, connection_type,
  honesty, support_after_check, founder_friendly_terms, responsiveness, hard_times
) on public.reviews to anon, authenticated;

grant insert (
  id, firm_id, fund_id, company_id, founder_person_id, partner_person_id,
  body, moderation_status, reviewed_on, created_at, updated_at, profile_id,
  anonymous, role_label, round_label, would_again, verification_method,
  connection_type, linkedin_url,
  honesty, support_after_check, founder_friendly_terms, responsiveness, hard_times
) on public.reviews to authenticated;

grant update (
  id, firm_id, fund_id, company_id, founder_person_id, partner_person_id,
  body, moderation_status, reviewed_on, created_at, updated_at, profile_id,
  anonymous, role_label, round_label, would_again, verification_method,
  connection_type, linkedin_url,
  honesty, support_after_check, founder_friendly_terms, responsiveness, hard_times
) on public.reviews to authenticated;

grant delete on public.reviews to authenticated;

create or replace function public.published_site_bundle()
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  with pub as (
    select id from firms where published and not is_test
  ),
  pub_matters as (
    select distinct matter_id as id
    from legal_matter_firms
    where firm_id in (select id from pub)
  ),
  pub_cards as (
    select id from evidence_cards where firm_id in (select id from pub)
  ),
  pub_sources as (
    select distinct source_id as id
    from fact_sources
    where firm_id in (select id from pub)
  ),
  pub_people as (
    select person_id as id from fund_people where firm_id in (select id from pub)
    union
    select founder_person_id from reviews where firm_id in (select id from pub) and founder_person_id is not null
    union
    select partner_person_id from reviews where firm_id in (select id from pub) and partner_person_id is not null
    union
    select board_person_id from investments where firm_id in (select id from pub) and board_person_id is not null
    union
    select cf.person_id
    from company_founders cf
    join investments i on i.company_id = cf.company_id
    where i.firm_id in (select id from pub)
  ),
  pub_companies as (
    select distinct company_id as id from investments where firm_id in (select id from pub)
  ),
  pub_press as (
    select press_item_id as id from press_item_firms where firm_id in (select id from pub)
  ),
  pub_results as (
    select id from score_results where firm_id in (select id from pub)
  ),
  pub_reviews as (
    select id from reviews where firm_id in (select id from pub)
  )
  select jsonb_build_object(
    'firms', coalesce((select jsonb_agg(to_jsonb(t) order by t.list_sort, t.slug) from firms t where t.id in (select id from pub)), '[]'::jsonb),
    'funds', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order, t.name) from funds t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'fund_entities', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from fund_entities t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'people', coalesce((select jsonb_agg(to_jsonb(t) order by t.full_name) from people t where t.id in (select id from pub_people)), '[]'::jsonb),
    'fund_people', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from fund_people t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'portfolio_companies', coalesce((select jsonb_agg(to_jsonb(t) order by t.name) from portfolio_companies t where t.id in (select id from pub_companies)), '[]'::jsonb),
    'company_founders', coalesce((select jsonb_agg(to_jsonb(t)) from company_founders t where t.company_id in (select id from pub_companies)), '[]'::jsonb),
    'investments', coalesce((select jsonb_agg(to_jsonb(t)) from investments t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'reviews', coalesce((
      select jsonb_agg(to_jsonb(t) order by t.reviewed_on nulls last, t.created_at)
      from (
        select
          id, firm_id, fund_id, company_id, founder_person_id, partner_person_id,
          body, first_hand, verification_status, moderation_status, reviewed_on,
          created_at, updated_at, profile_id, anonymous, role_label, round_label,
          would_again, verification_method, connection_type,
          honesty, support_after_check, founder_friendly_terms, responsiveness, hard_times
        from reviews
        where firm_id in (select id from pub)
      ) t
    ), '[]'::jsonb),
    'review_ratings', coalesce((select jsonb_agg(to_jsonb(t)) from review_ratings t where t.review_id in (select id from pub_reviews)), '[]'::jsonb),
    'legal_matters', coalesce((select jsonb_agg(to_jsonb(t)) from legal_matters t where t.id in (select id from pub_matters)), '[]'::jsonb),
    'legal_matter_firms', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from legal_matter_firms t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'legal_matter_parties', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from legal_matter_parties t where t.matter_id in (select id from pub_matters)), '[]'::jsonb),
    'filings', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from filings t where t.matter_id in (select id from pub_matters)), '[]'::jsonb),
    'docket_entries', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from docket_entries t where t.matter_id in (select id from pub_matters)), '[]'::jsonb),
    'legal_groups', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from legal_groups t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'legal_group_items', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from legal_group_items t where t.group_id in (select id from legal_groups where firm_id in (select id from pub))), '[]'::jsonb),
    'regulatory_records', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from regulatory_records t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'sanctions_checks', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from sanctions_checks t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'press_items', coalesce((select jsonb_agg(to_jsonb(t)) from press_items t where t.id in (select id from pub_press)), '[]'::jsonb),
    'press_item_firms', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from press_item_firms t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'sources', coalesce((select jsonb_agg(to_jsonb(t)) from sources t where t.id in (select id from pub_sources)), '[]'::jsonb),
    'fact_sources', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from fact_sources t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'takeaways', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from takeaways t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'ask_questions', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from ask_questions t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'copy_blocks', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from copy_blocks t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'page_chips', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from page_chips t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'firm_meta_items', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from firm_meta_items t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'list_items', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from list_items t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'portfolio_metrics', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from portfolio_metrics t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'firm_ranks', coalesce((select jsonb_agg(to_jsonb(t)) from firm_ranks t where t.firm_id in (select id from pub) and t.is_current), '[]'::jsonb),
    'evidence_cards', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from evidence_cards t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'evidence_lines', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from evidence_lines t where t.card_id in (select id from pub_cards)), '[]'::jsonb),
    'score_versions', coalesce((select jsonb_agg(to_jsonb(t)) from score_versions t), '[]'::jsonb),
    'score_sections', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from score_sections t), '[]'::jsonb),
    'score_results', coalesce((select jsonb_agg(to_jsonb(t)) from score_results t where t.id in (select id from pub_results)), '[]'::jsonb),
    'score_result_parts', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from score_result_parts t where t.result_id in (select id from pub_results)), '[]'::jsonb),
    'score_lines', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from score_lines t where t.result_id in (select id from pub_results)), '[]'::jsonb),
    'score_inputs', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from score_inputs t where t.result_id in (select id from pub_results)), '[]'::jsonb),
    'site_stats', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from site_stats t), '[]'::jsonb),
    'site_updates', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from site_updates t), '[]'::jsonb)
  );
$$;
