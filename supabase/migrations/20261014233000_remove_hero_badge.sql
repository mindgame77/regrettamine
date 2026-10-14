-- Alex (Oct 14 2026): remove the landing hero badge ("New · Lawsuits, regulators and conflicts, every source linked").
delete from public.ui_strings
where key in ('page.home.new', 'page.home.lawsuits_regulators_and_conflicts_every');
