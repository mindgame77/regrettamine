-- Stored report copy matches the page builder.
-- Rank rows follow the landing list (shown score, then name).
-- The founded-and-capped sentence is kept on the bonus row only.
-- Toxy is removed from evidence text so a later render cannot bring it back.
-- store_report_page also replaces the bundle HTML, which open_report uses when report_pages is empty.

create or replace function public.store_report_page(p_slug text, p_html text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_slug is null or p_html is null or p_slug !~ '^[a-z0-9-]{1,80}$' then
    raise exception 'invalid report page';
  end if;
  insert into public.report_pages (slug, html)
  values (p_slug, p_html)
  on conflict (slug) do update
    set html = excluded.html,
        updated_at = now();
  update public.report_bundles b
  set payload = jsonb_build_object('html', p_html),
      updated_at = now()
  from public.firms f
  where f.id = b.firm_id
    and f.slug = p_slug;
end;
$$;

update public.evidence_cards
set title = replace(replace(replace(replace(title, 'Toxy Score v2', 'Regrettamine score'), 'Toxy sources', 'sources'), 'Toxy''s ', ''), 'Toxy ', ''),
    body = replace(replace(replace(replace(body, 'Toxy Score v2', 'Regrettamine score'), 'Toxy sources', 'sources'), 'Toxy''s ', ''), 'Toxy ', '')
where title like '%Toxy%' or body like '%Toxy%';

update public.evidence_cards
set title = replace(title, 'Toxy', ''),
    body = replace(body, 'Toxy', '')
where title like '%Toxy%' or body like '%Toxy%';

update public.evidence_cards c
set title = '#' || r.place::text || ' of ' || r.total::text,
    body = regexp_replace(c.body, '^All 11 funds are (scored )?on v2\. *', '')
from (
  select id,
         row_number() over (order by list_score desc nulls last, name) as place,
         count(*) over () as total
  from public.firms
  where published and not is_test
) r
where c.firm_id = r.id
  and c.evidence_key = 'rank';

update public.evidence_lines l
set value = regexp_replace(l.value, ' \(v2\)$', ''),
    sort_order = ord.n
from (
  values
    ('Andreessen Horowitz', 0),
    ('Battery Ventures', 1),
    ('Bessemer Venture Partners', 2),
    ('Accel', 3),
    ('Bain Capital Ventures', 4),
    ('General Catalyst', 5),
    ('Khosla Ventures', 6),
    ('Lux Capital', 7),
    ('Sequoia Capital', 8),
    ('Lightspeed Venture Partners', 9),
    ('Insight Partners', 10)
) as ord(label, n)
where l.label = ord.label
  and l.card_id in (select id from public.evidence_cards where evidence_key = 'rank');

update public.score_lines age
set why = ''
from public.score_lines bonus
where age.name = 'Age default'
  and bonus.result_id = age.result_id
  and bonus.name = 'Years investing'
  and age.why = bonus.why
  and age.why like '%capped at +3%';
