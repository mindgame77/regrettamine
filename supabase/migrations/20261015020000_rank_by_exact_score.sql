-- Alex, Oct 14, 2026: rank by the exact (unrounded) score; the name breaks only true ties.
-- The list still shows the whole-number list_score.
alter table public.firms add column if not exists list_score_exact numeric(5,1);

update public.firms f
set list_score_exact = r.total
from public.score_results r
where r.firm_id = f.id and r.is_current and r.fund_id is null and r.total is not null;

CREATE OR REPLACE FUNCTION public.firm_list_row(f firms)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select jsonb_strip_nulls(jsonb_build_object(
    'id', f.slug,
    'name', f.name,
    'ini', f.initials,
    'short', f.short_name,
    'hq', f.hq,
    'metro', f.metro,
    'since', f.founded_year,
    'type', f.firm_type,
    'aum', f.aum_billions,
    'aumAsOf', f.aum_as_of,
    'aumStale', f.aum_stale,
    'aumSrc', f.aum_source,
    'score', f.list_score,
    'exact', f.list_score_exact,
    'v2', f.list_v2,
    'band', f.list_band,
    'legal', f.list_legal_active,
    'legalNote', f.legal_note,
    'updated', to_char(f.updated_on, 'YYYY-MM-DD'),
    'updatedTs', f.updated_ts,
    'updatedS', f.updated_label,
    'old', f.list_previous_score,
    'lo', f.list_range_low,
    'hi', f.list_range_high,
    'cov', f.list_coverage,
    'verdict', f.list_verdict,
    'report', f.report_slug
  ));
$function$;

CREATE OR REPLACE FUNCTION public.landing_funds()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tier text := public.access_tier();
  v_limit integer := public.tier_list_limit(v_tier);
  v_total integer;
  v_funds jsonb;
begin
  select count(*) into v_total
  from public.firms
  where published and not is_test;

  select coalesce(jsonb_agg(public.firm_list_row(f) order by ranked.rank), '[]'::jsonb)
  into v_funds
  from public.firms f
  join (
    select id, row_number() over (order by coalesce(list_score_exact, list_score) desc nulls last, name) as rank
    from public.firms
    where published and not is_test
  ) ranked on ranked.id = f.id
  where v_limit is null or ranked.rank <= v_limit;

  return jsonb_build_object(
    'tier', v_tier,
    'limit', v_limit,
    'total', v_total,
    'funds', v_funds
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.search_funds(q text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  cleaned text;
  v_tier text := public.access_tier();
  v_limit integer := public.tier_list_limit(v_tier);
  v_hits jsonb;
begin
  cleaned := left(regexp_replace(btrim(coalesce(q, '')), '[%_\\]', '', 'g'), 80);
  if cleaned = '' then
    return '[]'::jsonb;
  end if;

  select coalesce(jsonb_agg(
    case
      when v_limit is null or ranked.rank <= v_limit then
        public.firm_list_row(f) || jsonb_build_object(
          'slug', f.slug,
          'rank', ranked.rank,
          'inTier', true
        )
      else jsonb_build_object(
        'id', f.slug,
        'name', f.name,
        'slug', f.slug,
        'rank', ranked.rank,
        'inTier', false
      )
    end
    order by ranked.rank
  ), '[]'::jsonb)
  into v_hits
  from public.firms f
  join (
    select id, row_number() over (order by coalesce(list_score_exact, list_score) desc nulls last, name) as rank
    from public.firms
    where published and not is_test
  ) ranked on ranked.id = f.id
  where f.name ilike '%' || cleaned || '%'
     or f.slug ilike '%' || cleaned || '%';

  return v_hits;
end;
$function$;
