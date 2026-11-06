-- What investors look for: public.v2_investor_principles, read by v2_firm_page into sections key 'investors'.
-- Publication matches sibling v2 tables (v2_firm_industries, v2_firm_stages): RLS on, no anon policy.
-- The public page reads the rows through v2_firm_page (security definer). service_role manages the table.
-- The v2 schema is not created by repo migrations; on a database without v2_firms (CI) this is a no-op.
-- Undo: supabase/rollbacks/20261106010000_v2_investor_principles.sql
--
-- Seed is only quotes the 2026-11-05 research report marks EXACT, spoken while the person was at a16z,
-- with an actual publication date and an approved one-line summary from the layout mockup.
-- Seeded, in mockup order: Q15, Q16 (Alex Rampell, episode page 2026-01-14; quote text from the report transcript,
-- role_source_url is the a16z episode page because the transcript host is not the firm),
-- Q2 (Ben Horowitz, 2010-06-29), Q8 and Q10 (Marc Andreessen, a16z page posted 2016-05-30).
-- Left out on purpose: mockup speakers the report does not contain; Q1 Q3 Q4 Q5 Q6 Q7 (no approved summary);
-- Q9 (captions not re-fetched); Q11 and Q12 (2007, before the firm); Q13 (Dixon 2011);
-- Q14 (Dixon personal blog 2013-08-04, report does not prove he had joined).
do $mig$
declare
  d text;
  n text;
  old text := $old$    secs := secs || jsonb_build_object('key','overview','items',jsonb_build_array(jsonb_build_object('label','thesis','value',trim(f.thesis_text))));
  end if;$old$;
  new text := $new$    secs := secs || jsonb_build_object('key','overview','items',jsonb_build_array(jsonb_build_object('label','thesis','value',trim(f.thesis_text))));
  end if;
  -- What investors look for: sourced rows only. None = no section.
  select coalesce(jsonb_agg(jsonb_build_object(
      'investor_name',p.investor_name,'investor_title',p.investor_title,
      'summary',p.summary,'quote',p.quote,'published_at',p.published_at::text,'source_url',p.source_url)
      order by p.display_order, p.id),'[]') into it
    from v2_investor_principles p where p.firm_id=fid;
  if jsonb_array_length(it)>0 then secs := secs || jsonb_build_object('key','investors','items',it); end if;
  -- end What investors look for$new$;
begin
  if to_regclass('public.v2_firms') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;

  execute $ddl$create table if not exists public.v2_investor_principles (
  id bigint generated always as identity primary key,
  firm_id bigint not null references public.v2_firms(firm_id) on delete cascade,
  investor_name text not null check (btrim(investor_name) <> ''),
  investor_title text not null check (btrim(investor_title) <> ''),
  summary text not null check (char_length(btrim(summary)) between 1 and 200),
  quote text not null check (btrim(quote) <> '' and btrim(quote) <> btrim(summary)),
  published_at date not null,
  source_url text not null check (btrim(source_url) ~* '^https://'),
  role_source_url text check (role_source_url is null or btrim(role_source_url) ~* '^https://'),
  display_order int not null check (display_order >= 1),
  created_at timestamptz not null default now(),
  unique (firm_id, display_order)
)$ddl$;

  execute $rls$alter table public.v2_investor_principles enable row level security;
revoke all on table public.v2_investor_principles from public, anon, authenticated$rls$;

  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant select, insert, update, delete on table public.v2_investor_principles to service_role';
    execute 'grant usage, select on sequence public.v2_investor_principles_id_seq to service_role';
  end if;

  comment on table public.v2_investor_principles is 'What investors look for. The public page reads rows through v2_firm_page. role_source_url is the firm page that proves the speaker was at the firm when source_url is not the firm site.';
  comment on column public.v2_investor_principles.role_source_url is 'Firm site confirming the speaker role when source_url does not. Not shown on the page.';

  execute $seed$insert into public.v2_investor_principles
  (firm_id, display_order, investor_name, investor_title, summary, quote, published_at, source_url, role_source_url)
select f.firm_id, v.display_order, v.investor_name, v.investor_title, v.summary, v.quote, v.published_at, v.source_url, v.role_source_url
  from public.v2_firms f
  cross join (values
    (1, 'Alex Rampell', 'General Partner', $qQ15s$Attract people, capital and customers; know the space’s history; show personal drive.$qQ15s$, $qQ15$I gotta say, like the best entrepreneurs, they have five things that I look for. They can materialize labor capital and customers, and hopefully those are self-evidence. Like, you can get people to quit their high-paying job for certain failure. … Then you want to know the history of the space, which is super important to your point. … This person knows everything that’s tried before and they have a new angle of attack. They’re not going to learn on the job. They’ve actually learned through history. And then the last thing that I care about a lot … you either want revenge or redemption. And some of the best entrepreneurs have this in common.$qQ15$, date '2026-01-14', 'https://podscripts.co/podcasts/the-a16z-show/alex-rampell-on-tbpn-revenge-redemption-and-founder-drive', 'https://a16z.com/podcast/alex-rampell-on-tbpn-revenge-redemption-and-founder-drive/'),
    (2, 'Alex Rampell', 'General Partner', $qQ16s$Build strong customer retention and get distribution before incumbents copy your innovation.$qQ16s$, $qQ16$there’s a quote that I use a lot, the best companies have hostages, not customers. … And another expression I use a lot is like the battle between every startup and incumbent is whether the startup gets the distribution before the incumbent gets the innovation. My default assumption is that the incumbent normally wins.$qQ16$, date '2026-01-14', 'https://podscripts.co/podcasts/the-a16z-show/alex-rampell-on-tbpn-revenge-redemption-and-founder-drive', 'https://a16z.com/podcast/alex-rampell-on-tbpn-revenge-redemption-and-founder-drive/'),
    (3, 'Ben Horowitz', 'Cofounder and General Partner', $qQ2s$We prefer founding CEOs who keep—and ideally created—the product vision.$qQ2s$, $qQ2$We prefer founding CEOs. In particular, we think the keeper of the product vision should run the company whenever possible because the toughest and most important decisions in technology companies are always about product strategy. The only thing better than the CEO being the keeper of the vision is the CEO being the creator of the vision.$qQ2$, date '2010-06-29', 'https://a16z.com/announcement/why-andreessen-horowitz-invested-in-foursquare/', null::text),
    (4, 'Marc Andreessen', 'Cofounder and General Partner', $qQ8s$Invest in distinctive strength that stands out—not merely a lack of weakness across team, product, and market.$qQ8s$, $qQ8$We talk a lot in our firm about — we have this concept — we say, “We invest in strength, not in lack of weakness.” And again, it’s one of these things that sounds obvious, but it’s proved to us to be a pretty big deal. So, there’s a lot of startups you’ll run into, or you probably have friends who are at these companies or know people at them, and it’s like, team’s good, product’s good, market seems good, they’re making some progress, they’ve got some customers, the customers are pretty happy. Okay. Where is that really gonna go, and where is it really gonna go? Because what’s spectacular about it, right? What’s the thing that’s gonna cause it to jump out from the other hundred, or other thousand companies where you can say the exact same thing?$qQ8$, date '2016-05-30', 'https://a16z.com/podcast/a16z-podcast-startups-and-pendulum-swings-through-ideas-time-fame-and-money/', null::text),
    (5, 'Marc Andreessen', 'Cofounder and General Partner', $qQ10s$Look for founder-market fit: the person born to do that idea.$qQ10s$, $qQ10$There’s another concept we call founder-market fit, which is — is the founder of a company — is that the person who’s born to do that idea? And so, that question we tend to defer to the founders, because we figured the really great founders are gonna figure that — like, part of what makes a founder great is they’re gonna figure that out. The other thing we found is that it’s very hard — we have ideas for companies we’d like to fund, but we try not to talk about them too much, because we don’t want somebody — we don’t want founders to pick up somebody else’s idea.$qQ10$, date '2016-05-30', 'https://a16z.com/podcast/a16z-podcast-startups-and-pendulum-swings-through-ideas-time-fame-and-money/', null::text)
  ) as v(display_order, investor_name, investor_title, summary, quote, published_at, source_url, role_source_url)
 where f.slug = 'a16z'
on conflict (firm_id, display_order) do nothing$seed$;

  if to_regprocedure('public.v2_firm_page(text)') is null then
    raise notice 'v2_firm_page missing, table only';
    return;
  end if;
  select pg_get_functiondef('public.v2_firm_page(text)'::regprocedure) into d;
  if position('-- What investors look for:' in d) > 0 then
    raise notice 'v2_firm_page investors already patched';
    return;
  end if;
  if position(old in d) = 0 then
    raise exception 'v2_firm_page: thesis anchor not found';
  end if;
  n := replace(d, old, new);
  if position('-- What investors look for:' in n) = 0 or position('''key'',''investors''' in n) = 0 then
    raise exception 'v2_firm_page: investors patch did not apply';
  end if;
  execute n;
end
$mig$;
