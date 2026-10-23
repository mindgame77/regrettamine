-- Regretamin launch (option A): gray locked outline per fact, public. Additive (new function only).
-- Returns ONLY row, kind, year, status per fact. No case names, parties, people, courts/dockets, list names,
-- sources, summaries or links. Built from firm_details() so the fact set and counts match the unlocked view.
-- status/kind mirror launch/js/app.js caseStatus()/isCase() (status wording in the fact text); kind is rule-based.
create or replace function public.firm_case_outline(p_slug text) returns json
language sql stable security definer set search_path = public as $$
  with fm as (select id from firms where slug = p_slug and deleted_at is null and published),
  r as (select (e->>'row')::int rn, e->'facts' facts from fm, json_array_elements(public.firm_details(fm.id)) e),
  x as (
    select rn, ord, t, c, who, coalesce(y, substring(t from 'filed ((?:19|20)\d\d)')) yr,
      (c is not null or t ~* ' v\.? .*\|.*\y(filed|terminated)\y') is_case
    from r, json_array_elements(r.facts) with ordinality as j(f, ord),
      lateral (select coalesce(f->>'text','') t, f->>'case' c, f->>'who' who, f->>'year' y) v
  ), s as (
    select x.*,
      case when not is_case then null
        when t ~* '\y(active|pending|ongoing)\y|\yopen\y[,.;:]|\yis investigating\y' then 'active'
        when t ~* '\youtcome (unverified|not verified)\y' then null
        when t ~* '\y(terminated|dismissed|ended in|settled|resolved|closed|affirmed)\y' then 'closed'
      end status,
      case
        when is_case and t ~* '\y(investigat\w*|probe)\y' then 'Government probe'
        when is_case and t ~* 'class action' then 'Class action'
        when is_case and t ~* 'subpoena' then 'Subpoena'
        when is_case and (who like 'partner:%' or t ~* '\yas an? [a-z]+ director\y|\yrole as\y') then 'Suit naming a partner'
        when is_case and t ~* '\y(plaintiff|backed|joined a suit)\y' then 'Suit brought or backed by the firm'
        when is_case then 'Court case'
        when rn = 10 and t ~* '\yPEP\y' then 'Political-role match'
        when rn = 10 then 'Political-role screen'
        when rn = 8 then 'Registry record'
        when t ~* 'Form ADV|disclosure' then 'Regulator filing'
        when rn = 7 then 'Case-law search'
        else 'List screening'
      end kind
    from x
  )
  select coalesce(json_agg(json_build_object('row', rn, 'items', items) order by rn), '[]'::json) from (
    select rn, json_agg(json_build_object('kind', kind, 'year', yr, 'status', status)
      order by (status = 'active') desc nulls last, ord) items
    from s group by rn) g
$$;
revoke all on function public.firm_case_outline(text) from public;
grant execute on function public.firm_case_outline(text) to anon, authenticated;
