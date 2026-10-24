-- firm_aliases: every old / alternate name stays searchable; firm_suggest returns the firm's current display name.
create table if not exists public.firm_aliases (
  firm_id uuid not null references public.firms(id) on delete cascade,
  alias text not null check (btrim(alias) <> ''),
  source text not null check (source in ('sec_legal', 'previous_display', 'queue_name')),
  created_at timestamptz not null default now()
);
create unique index if not exists firm_aliases_firm_alias_key on public.firm_aliases (firm_id, lower(alias));
create index if not exists firm_aliases_lower_alias_idx on public.firm_aliases (lower(alias) text_pattern_ops);
alter table public.firm_aliases enable row level security;
revoke all on public.firm_aliases from anon, authenticated;

-- previous display names (backups/firms_display_hq_changes_2026-10-24.csv, old_display)
insert into firm_aliases (firm_id, alias, source)
select f.id, v.alias, 'previous_display' from (values
  ('010118-management', '010118 Management'),
  ('1sharpe-capital', '1sharpe Capital'),
  ('776-management', '776 Management'),
  ('83north-2017', '83north 2017'),
  ('a-capital-ventures', 'A.capital Ventures'),
  ('accel', 'Accel'),
  ('accel-london-management', 'Accel London Management'),
  ('accel-partners', 'Accel Partners'),
  ('accomplice-management', 'Accomplice Management'),
  ('adams-street-partners', 'Adams Street Partners'),
  ('alkeon-capital', 'Alkeon Capital'),
  ('alpha-square-group-s', 'Alpha Square Group S'),
  ('altimeter', 'Altimeter'),
  ('apple-tree-venture', 'Apple Tree Venture'),
  ('aquiline-management-holdings', 'Aquiline Management Holdings'),
  ('at-one-ventures-opco', 'At One Ventures Opco'),
  ('atlas-venture-life-science-advisors', 'Atlas Venture Life Science Advisors'),
  ('atomico-management', 'Atomico Management'),
  ('atomico-uk-partners', 'Atomico (Uk) Partners'),
  ('avf-management', 'AVF Management'),
  ('avoro-capital-advisors', 'Avoro Capital Advisors'),
  ('balyasny-asset-management', 'Balyasny Asset Management'),
  ('banyan-capital-partners', 'Banyan Capital Partners'),
  ('battery-management', 'Battery Management'),
  ('bedrock-fund-management', 'Bedrock Fund Management'),
  ('benchmark-capital-holdings', 'Benchmark Capital Holdings'),
  ('bessemer-venture-partners', 'Bessemer Venture Partners'),
  ('blackbird-ventures', 'Blackbird Ventures'),
  ('blackstone-strategic-partners', 'Blackstone Strategic Partners'),
  ('blue-cloud-management', 'Blue Cloud Management'),
  ('boxgroup-ventures', 'BoxGroup Ventures'),
  ('brightwood-capital-advisors', 'Brightwood Capital Advisors'),
  ('coatue', 'Coatue'),
  ('congruent-management', 'Congruent Management'),
  ('creandum-fund-manager', 'Creandum Fund Manager'),
  ('creandum-v-advisor', 'Creandum V Advisor'),
  ('cyberstarts-venture-fund', 'Cyberstarts Venture Fund'),
  ('dimension-management', 'Dimension Management'),
  ('dragonfly-digital-management', 'Dragonfly Digital Management'),
  ('east-ventures-advisory', 'East Ventures Advisory'),
  ('ecor1-capital', 'Ecor1 Capital'),
  ('eight-partners-vc', 'Eight Partners VC'),
  ('eight-roads', 'Eight Roads'),
  ('electric-capital-partners', 'Electric Capital Partners'),
  ('emergence-equity', 'Emergence Equity'),
  ('encap-investments', 'EnCap Investments'),
  ('eqt-fund-management', 'EQT Fund Management'),
  ('esp-investment-advisors', 'ESP Investment Advisors'),
  ('felix-capital', 'Felix Capital'),
  ('fifth-down-cap', 'Fifth Down Cap'),
  ('fifth-wall-asset-management', 'Fifth Wall Asset Management'),
  ('founders-fund', 'Founders Fund'),
  ('fpv-management', 'FPV Management'),
  ('frazier-life-sciences-management', 'Frazier Life Sciences Management'),
  ('georgian-partners-growth', 'Georgian Partners Growth'),
  ('gimpel-private-markets', 'Gimpel Private Markets'),
  ('golden-sand-river', 'Golden Sand River'),
  ('greenoaks', 'Greenoaks'),
  ('h-i-g-capital', 'H.I.G. Capital'),
  ('hedosophia-advisor', 'Hedosophia Advisor'),
  ('hof-capital', 'Hof Capital'),
  ('hony-capital', 'Hony Capital'),
  ('horsley-bridge-partners', 'Horsley Bridge Partners'),
  ('hv-capital-manager', 'HV Capital Manager'),
  ('ia-capital-advisors', 'IA Capital Advisors'),
  ('idg-capital-fund-management', 'IDG Capital Fund Management'),
  ('idg-vc-management', 'IDG VC Management'),
  ('impresa-management', 'Impresa Management'),
  ('institutional-venture-management-xv', 'Institutional Venture Management XV'),
  ('institutional-venture-management-xvi', 'Institutional Venture Management XVI'),
  ('institutional-venture-management-xvii', 'Institutional Venture Management XVII'),
  ('institutional-venture-management-xviii', 'Institutional Venture Management XVIII'),
  ('k1', 'K1'),
  ('k5-global-advisor', 'K5 Global Advisor'),
  ('kairos-managers', 'Kairos Managers'),
  ('kaszek-management', 'Kaszek Management'),
  ('khosla-ventures', 'Khosla Ventures'),
  ('kleiner-perkins', 'Kleiner Perkins'),
  ('lav-investment-adviser', 'LAV Investment Adviser'),
  ('layer-global-management', 'Layer Global Management'),
  ('lcv-blockchain-management', 'LCV Blockchain Management'),
  ('logos-global-management', 'Logos Global Management'),
  ('matrix-partners-india-management', 'Matrix Partners India Management'),
  ('medicxi-ventures-management-jersey', 'Medicxi Ventures Management (Jersey)'),
  ('mercato-management-legacy', 'Mercato Management Legacy'),
  ('mfo-asset-management', 'MFO Asset Management'),
  ('mio-partners', 'MIO Partners'),
  ('momentum-capital-partners-alpha-advisor', 'Momentum Capital Partners Alpha Advisor'),
  ('momentum-capital-partners-fund-iv-advisor', 'Momentum Capital Partners Fund IV Advisor'),
  ('morgan-stanley-capital-partners', 'Morgan Stanley Capital Partners'),
  ('mpm-bioimpact', 'MPM Bioimpact'),
  ('nea', 'NEA'),
  ('next-legacy-management', 'Next Legacy Management'),
  ('nexus-ventures', 'Nexus Ventures'),
  ('nexus-ventures-advisors', 'Nexus Ventures Advisors'),
  ('nrep', 'NREP'),
  ('nsv-management', 'NSV Management'),
  ('oakley-capital-manager', 'Oakley Capital Manager'),
  ('openai-startup-fund-management', 'OpenAI Startup Fund Management'),
  ('partners-group', 'Partners Group'),
  ('peak-xv-partners-operations', 'Peak XV Partners Operations'),
  ('pearl-energy-investment-management-iii', 'Pearl Energy Investment Management III'),
  ('pearl-energy-investment-management-iv', 'Pearl Energy Investment Management IV'),
  ('phoenix-court-fund-management', 'Phoenix Court Fund Management'),
  ('pinegrove-venture-partners', 'Pinegrove Venture Partners'),
  ('project-a', 'Project A'),
  ('qiming-global-management', 'Qiming Global Management'),
  ('ribbit-capital', 'Ribbit Capital'),
  ('sagard-holdings-manager', 'Sagard Holdings Manager'),
  ('sali-fund-services', 'SALI Fund Services'),
  ('saluda-grade-asset-management', 'Saluda Grade Asset Management'),
  ('scottish-equity-partners', 'Scottish Equity Partners'),
  ('select-equity-group', 'Select Equity Group'),
  ('sierra-ventures-management-iii', 'Sierra Ventures Management III'),
  ('sky9-capital', 'Sky9 Capital'),
  ('sound-development', 'Sound Development'),
  ('stepstone', 'StepStone'),
  ('stonepeak', 'Stonepeak'),
  ('sv-health-managers', 'SV Health Managers'),
  ('team8', 'Team8'),
  ('threshold-management', 'Threshold Management'),
  ('threshold-ventures-ii', 'Threshold Ventures II'),
  ('thrive-capital', 'Thrive Capital'),
  ('transpose-platform-management', 'Transpose Platform Management'),
  ('updata-partners', 'Updata Partners'),
  ('uprising-management', 'Uprising Management'),
  ('valor-equity-partners', 'Valor Equity Partners'),
  ('venrock-management', 'Venrock Management'),
  ('versant-venture', 'Versant Venture'),
  ('west-rim-capital-associates-ii', 'West Rim Capital Associates II'),
  ('west-rim-ii-ugp', 'West Rim II UGP'),
  ('westbridge-capital-us-advisors', 'Westbridge Capital US Advisors'),
  ('y-combinator', 'Y Combinator')
) v(slug, alias) join firms f on f.slug = v.slug
on conflict do nothing;

-- SEC legal names
insert into firm_aliases (firm_id, alias, source)
select id, btrim(legal_name), 'sec_legal' from firms where coalesce(btrim(legal_name), '') <> ''
on conflict do nothing;

-- queue / registry names of each firm's linked entry and merged duplicates
insert into firm_aliases (firm_id, alias, source)
select distinct on (f.id, lower(btrim(q.name))) f.id, btrim(q.name), 'queue_name' from firms f
join research_queue q on f.registry_id is not null and (q.registry_id = f.registry_id or q.duplicate_of = f.registry_id)
where coalesce(btrim(q.name), '') <> ''
on conflict do nothing;

create or replace function public.firm_suggest(q text)
 returns json language sql stable security definer set search_path to 'public'
as $fn$
  with t as (select lower(trim(q)) t), pub as (
    select f.* from firms f where f.published and not coalesce(f.is_test, false) and f.data_status = 'real' and f.deleted_at is null
  ), m as (
    select f.slug, coalesce(f.display_name, f.name) as name, f.short_name, f.hq,
      case when lower(coalesce(f.display_name, f.name)) like t || '%' or lower(coalesce(f.short_name, '')) like t || '%' or f.slug like t || '%' then 0
           when lower(coalesce(f.display_name, f.name)) ~ ('\m' || regexp_replace(t, '([^a-z0-9 ])', '\\\1', 'g')) then 1 else 2 end r
    from pub f, t
    where length(t) > 0
      and (lower(coalesce(f.display_name, f.name)) like '%' || t || '%' or lower(coalesce(f.short_name, '')) like '%' || t || '%' or f.slug like '%' || t || '%')
    union all
    select f.slug, coalesce(f.display_name, f.name), f.short_name, f.hq,
      case when lower(a.alias) like t || '%' then 0 when lower(a.alias) ~ ('\m' || regexp_replace(t, '([^a-z0-9 ])', '\\\1', 'g')) then 1 else 2 end
    from firm_aliases a join pub f on f.id = a.firm_id, t
    where length(t) > 0 and lower(a.alias) like '%' || t || '%'
  ), d as (select slug, name, short_name, hq, min(r) r from m group by slug, name, short_name, hq)
  select coalesce(json_agg(json_build_object('slug', slug, 'name', name, 'short_name', short_name, 'hq', hq) order by r, name), '[]')
  from (select * from d order by r, name limit 8) x
$fn$;

CREATE OR REPLACE FUNCTION public.ensure_firm_for_registry(p_registry text, p_fill boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t text := _registry_target(p_registry); q research_queue; fid uuid; created boolean := false; researched boolean;
  dn text; base text; slg text; sfx int := 1; dom text; hq text; linked int := 0;
begin
  select * into q from research_queue where registry_id = t;
  if q.registry_id is null then return null; end if;
  researched := exists (select 1 from research_submissions s where s.registry_id in (t, p_registry) and s.valid);
  if nullif(q.sec_crd, '') is not null then
    select id into fid from firms where sec_crd = q.sec_crd and deleted_at is null order by published desc limit 1;
  end if;
  if fid is null then select id into fid from firms where registry_id = t and deleted_at is null; end if;
  if fid is not null then
    update firms set registry_id = t where id = fid and registry_id is null and not exists (select 1 from firms o where o.registry_id = t);
    if researched then
      update firms set published = true where id = fid and not published and not coalesce(is_test, false) and data_status = 'real';
    end if;
  else
    dn := coalesce(firm_display_name(q.name), q.name);
    base := coalesce(_slugify(dn), lower(t)); slg := base;
    while exists (select 1 from firms where slug = slg) loop sfx := sfx + 1; slg := base || '-' || sfx; end loop;
    dom := substring(lower(btrim(coalesce(q.website, ''))) from '^(?:[a-z]+://)?(?:www\.)?([^/:?#\s]+)');
    if dom is null or dom !~ '\.' or dom ~ '(^|\.)(linkedin|x|twitter|instagram|facebook|youtube|crunchbase|medium|github|angel|wellfound|pitchbook)\.(com|co|io)$' then dom := null; end if;
    hq := firm_hq_format(q.hq_city, q.state, q.country);
    insert into firms (slug, name, display_name, legal_name, hq, sec_crd, primary_domain, firm_type, data_status, source_system, external_id,
                       registry_id, published)
    values (slg, dn, dn, q.name, hq, nullif(q.sec_crd, ''), dom, case when q.firm_type = 'vc' then 'VC' end, 'real', 'research', t,
            t, researched)
    returning id into fid;
    created := true;
    insert into firm_check_rows (firm_id, n, title, descr, state, count_label)
    select fid, x.n, x.title, x.descr, 'nc', null from (values
      (1, 'Sanctions', 'Government lists of people and companies you can''t do business with.'),
      (2, 'Terrorism financing lists', 'Lists of people and groups linked to funding terrorism.'),
      (3, 'Export and investment restrictions', 'Trade or investment bans, e.g. deals with military-linked firms.'),
      (4, 'Financial regulator actions', 'Fines, bans and charges from financial regulators.'),
      (5, 'Money laundering penalties', 'Anti-money-laundering fines and enforcement.'),
      (6, 'US court records', 'Federal and state cases, civil and criminal.'),
      (7, 'Court records worldwide', 'Cases outside the U.S.'),
      (8, 'Registration check', 'Registered with the regulator as an investment adviser, and active.'),
      (9, 'People behind the fund', 'Partners and owners, each checked against the lists above.'),
      (10, 'Political ties', 'People at the firm who held government or political roles.')) x(n, title, descr)
    on conflict (firm_id, n) do nothing;
  end if;
  -- keep the legal / queue name searchable as an alias (firm_suggest)
  insert into firm_aliases (firm_id, alias, source)
  select fid, a.alias, a.source from (values (btrim(q.name), 'queue_name'),
    (btrim((select legal_name from firms where id = fid)), 'sec_legal')) a(alias, source)
  where coalesce(a.alias, '') <> ''
  on conflict do nothing;
  -- link enrichments / search log rows that arrived before the page existed (rows are not copied, so re-sends never duplicate)
  update research_enrichments set firm_id = fid where firm_id is null and registry_id in (t, p_registry);
  get diagnostics linked = row_count;
  update search_log set firm_id = fid where firm_id is null and registry_id in (t, p_registry);
  if p_fill or created then
    begin perform apply_checks_for_firm(fid); exception when others then raise warning 'ensure_firm %: checks: %', t, sqlerrm; end;
    begin perform promote_bot_facts(fid); exception when others then raise warning 'ensure_firm %: bot facts: %', t, sqlerrm; end;
  end if;
  if p_fill or created or linked > 0 then
    begin perform promote_enrichment(fid); exception when others then raise warning 'ensure_firm %: enrichment: %', t, sqlerrm; end;
  end if;
  return fid;
end $function$;
