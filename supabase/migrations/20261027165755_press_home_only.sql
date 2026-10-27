-- Press step 5, proposed, not applied.
-- The site export stops carrying press rows from vc_source_facts.
-- Those rows stay in the table. Nothing is updated or deleted.
-- Firm-page News already reads press_items + press_item_firms
-- where check_mark = 'checked_correct' (press_check_mark). The page
-- stops drawing timeline into News in launch/js/company.js.
--
-- Rollback: put the vc_source_facts select back without
-- `and t.fact_type <> 'press_item'`. Revert this pull request.
-- No rows are deleted.

CREATE OR REPLACE FUNCTION public.published_site_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with pub as (
    select id, slug from firms where published and indexable and not is_test
  )
  select public.published_site_core() || jsonb_build_object(
    'vc_source_facts', coalesce((select jsonb_agg(to_jsonb(t) || jsonb_build_object('slug', p.slug) order by p.slug, t.section, t.created_at, t.id)
      from vc_source_facts t join pub p on p.id = t.firm_id
      where t.data_status = 'real' and t.superseded_by is null and t.fact_type <> 'press_item'), '[]'::jsonb),
    'vc_entity_identifiers', coalesce((select jsonb_agg(to_jsonb(t) || jsonb_build_object('slug', p.slug) order by p.slug, t.id_type, t.value)
      from vc_entity_identifiers t join pub p on p.id = t.firm_id where t.data_status = 'real'), '[]'::jsonb),
    'vc_partner_history', coalesce((select jsonb_agg(to_jsonb(t) || jsonb_build_object('slug', p.slug) order by p.slug, t.person_name, t.id)
      from vc_partner_history t join pub p on p.id = t.firm_id where t.data_status = 'real'), '[]'::jsonb),
    'vc_political_activity', coalesce((select jsonb_agg(to_jsonb(t) || jsonb_build_object('slug', p.slug) order by p.slug, t.person_name, t.id)
      from vc_political_activity t join pub p on p.id = t.firm_id where t.data_status = 'real'), '[]'::jsonb),
    'vc_context_notes', coalesce((select jsonb_agg(to_jsonb(t) || jsonb_build_object('slug', p.slug) order by p.slug, t.retrieved_at, t.value)
      from vc_context_notes t join pub p on p.id = t.firm_id where t.data_status = 'real'), '[]'::jsonb)
  );
$function$;
