-- CI only: the generated data migrations (company page / research import) look up
-- production firms by slug. A fresh test database has none, so seed the slugs they reference.
insert into public.firms(slug, name) values
  ('a16z', 'Andreessen Horowitz'),
  ('nb-alternatives', 'NB Alternatives')
on conflict (slug) do nothing;
