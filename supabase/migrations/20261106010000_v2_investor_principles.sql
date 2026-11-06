-- What investors look for: public.v2_investor_principles, read by v2_firm_page into sections key 'investors'.
-- Publication matches sibling v2 tables (v2_firm_industries, v2_firm_stages): RLS on, no anon policy.
-- The public page reads the rows through v2_firm_page (security definer). service_role manages the table.
-- The v2 schema is not created by repo migrations; on a database without v2_firms (CI) this is a no-op.
-- Undo: supabase/rollbacks/20261106010000_v2_investor_principles.sql
--
-- Seed: 12 a16z rows whose sources establish the speaker was an a16z investor at the quote date (E3).
-- role_source_url is set only when the quote URL is not itself the firm's page.
-- Order is the approved mockup: the recent five first, then the other designed rows that pass E3.
-- 1 Andrew Chen 2026-10-30 C7, a16z essay byline (GP, speedrun).
-- 2 Sarah Wang 2026-05-20 C18, a16z announcement byline (GP, Growth).
-- 3 Alex Rampell 2026-01-14 Q15, wording from the report transcript; role_source_url is the a16z episode page.
-- 4 Jeff Jordan 2023-09-19 C11, a16z essay byline (GP, consumer). Publication date is the quote date.
-- 5 Anish Acharya 2022-09-15 C4, a16z announcement byline (GP).
-- 6 Alex Rampell 2026-01-14 Q16, same episode and role proof as Q15; different selection point.
-- 7 Martin Casado 2022-06-09 C9, a16z essay byline (GP, infrastructure).
-- 8 Jeff Jordan 2021-06-02 C12, a16z announcement byline (GP, consumer).
-- 9 Seema Amble 2022-10-05 C14, a16z announcement byline (Partner).
-- 10 Ben Horowitz 2010-06-29 Q2, a16z investment note (co-founder and GP).
-- 11 Marc Andreessen 2016-05-30 Q8, a16z podcast transcript (co-founder and GP).
-- 12 Marc Andreessen 2016-05-30 Q10, same a16z transcript.
-- Not seeded: pre-a16z (Marc 2007, Dixon 2011), Dixon 2013 (role date not proved), Marc Stanford Q9 (captions not re-fetched),
-- and older or overlapping notes that are not the approved twelve (Yoo 2020, Acharya 2020, Chen 2019, Casado 2018 and 2020,
-- George 2020, Chan 2021, Wang 2021, Li 2023, Ben's other 2010-2011 notes, Marc's 2016 ranking passage).
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
    (1, 'Andrew Chen', 'General Partner, speedrun', $qC7s$You don’t need one standard founder background—know the strengths and gaps of yours.$qC7s$, $qC7$I think we’ll most certainly see a rapid expansion in the types of founder archetypes building new products. That’s a good thing. We’ll see high failure rates, inevitably, but some of them will work. Some of the archetypes – like kids/high schoolers – have some huge advantages but lack domain expertise. The archetypes with lots of domain expertise, like dentists building AI dentist software, have lots of experience but might lack an outsider’s disruptive mindset. There’s pros and cons to each, but building a bigger tent in the founder community can only be a good thing.$qC7$, date '2026-10-30', 'https://a16z.com/new-founder-archetypes-in-the-ai-age/', null::text),
    (2, 'Sarah Wang', 'Growth', $qC18s$Show customers already choose your product first for an important, difficult job.$qC18s$, $qC18$The signal from the market was consistent. Exa excels with the hardest queries – the long tail of high alpha searches where traditional engines fail. It stands out on low latency where it matters, especially time to first token, which matters acutely in user-facing agent flows. What struck us most was the default behavior: developers and agents are reaching for Exa first. As one customer put it, “this is the default for getting agents to do web search now.” No ordinary team would take on such a grand vision: building a search engine from scratch for AI.$qC18$, date '2026-05-20', 'https://a16z.com/announcement/investing-in-exa/', null::text),
    (3, 'Alex Rampell', 'General Partner', $qQ15s$Attract people, capital and customers; know the space’s history; show personal drive.$qQ15s$, $qQ15$I gotta say, like the best entrepreneurs, they have five things that I look for. They can materialize labor capital and customers, and hopefully those are self-evidence. Like, you can get people to quit their high-paying job for certain failure. … Then you want to know the history of the space, which is super important to your point. … This person knows everything that’s tried before and they have a new angle of attack. They’re not going to learn on the job. They’ve actually learned through history. And then the last thing that I care about a lot … you either want revenge or redemption. And some of the best entrepreneurs have this in common.$qQ15$, date '2026-01-14', 'https://podscripts.co/podcasts/the-a16z-show/alex-rampell-on-tbpn-revenge-redemption-and-founder-drive', 'https://a16z.com/podcast/alex-rampell-on-tbpn-revenge-redemption-and-founder-drive/'),
    (4, 'Jeff Jordan', 'General Partner, consumer', $qC11s$Lead with founder/product fit and real strengths—not just a lack of weaknesses.$qC11s$, $qC11$Beyond the metrics, co-founder and CEO Apoorva Mehta had great founder/product fit. Prior to founding Instacart, Apoorva was a fulfillment optimization software engineer from Amazon. He was the perfect leader for a concept that would require constant optimization to be successful. a16z has long had an investment theory that we should invest behind strengths of a business model and opportunity, not lack of weakness. Instacart is a case study of this. Focusing on the former was key to our investment decision.$qC11$, date '2023-09-19', 'https://a16z.com/instacart/', null::text),
    (5, 'Anish Acharya', 'General Partner', $qC4s$Show your experience makes you unusually suited to build this product.$qC4s$, $qC4$At the end of the day, businesses are about the teams that build them, and Gary is exactly the type of founder and leader we like to back. He’s consistently built and sold payment processors for emerging forms of risk (Wildcard Systems, which sold to eFunds; eFunds to FIS; and Adaptive Payments, which sold to Mastercard) and the product he’s building now is totally authentic to his experiences.$qC4$, date '2022-09-15', 'https://a16z.com/announcement/investing-in-payall/', null::text),
    (6, 'Alex Rampell', 'General Partner', $qQ16s$Build strong customer retention and get distribution before incumbents copy your innovation.$qQ16s$, $qQ16$there’s a quote that I use a lot, the best companies have hostages, not customers. … And another expression I use a lot is like the battle between every startup and incumbent is whether the startup gets the distribution before the incumbent gets the innovation. My default assumption is that the incumbent normally wins.$qQ16$, date '2026-01-14', 'https://podscripts.co/podcasts/the-a16z-show/alex-rampell-on-tbpn-revenge-redemption-and-founder-drive', 'https://a16z.com/podcast/alex-rampell-on-tbpn-revenge-redemption-and-founder-drive/'),
    (7, 'Martin Casado', 'General Partner, infrastructure', $qC9s$Explain why your infrastructure company can compete directly with the major cloud providers.$qC9s$, $qC9$The primary question to startups in infrastructure has ironically shifted from “ what if AWS/GCP/Azure decides to compete with you? ” to “w hy aren’t you competing more directly with AWS/GCP/Azure? ”$qC9$, date '2022-06-09', 'https://a16z.com/the-cloud-killed-infrastructure-long-live-infrastructure/', null::text),
    (8, 'Jeff Jordan', 'General Partner, consumer', $qC12s$Look for marketplace businesses that create strong multi-sided value and network effects for scale and defensibility.$qC12s$, $qC12$Here are a few of the reasons I like marketplace business: They can create magical value propositions for their users, be they two-sided (e.g., eBay connecting buyers to sellers) or three-sided networks (e.g., Instacart connecting shoppers to grocery stores and picking/delivery gig workers). … If they work, they tend to develop network effects. The more restaurants OpenTable added, the more valuable they became to consumers. And the more consumers used OpenTable, the easier it was to attract restaurants. These network effects drive increasing returns to scale and create defensibility barriers for the business.$qC12$, date '2021-06-02', 'https://a16z.com/announcement/investing-in-shef/', null::text),
    (9, 'Seema Amble', 'Partner', $qC14s$Start with a high-velocity, tenacious founder who has lived the problem personally.$qC14s$, $qC14$Any investment starts and ends with a team, and Michael Colin is one of the highest velocity and most tenacious founders we’ve backed. And he has lived the problem himself. He broke into the freight market working as a broker to help pay his way through college.$qC14$, date '2022-10-05', 'https://a16z.com/announcement/investing-in-mvmnt/', null::text),
    (10, 'Ben Horowitz', 'Cofounder and General Partner', $qQ2s$We prefer founding CEOs who keep—and ideally created—the product vision.$qQ2s$, $qQ2$We prefer founding CEOs. In particular, we think the keeper of the product vision should run the company whenever possible because the toughest and most important decisions in technology companies are always about product strategy. The only thing better than the CEO being the keeper of the vision is the CEO being the creator of the vision.$qQ2$, date '2010-06-29', 'https://a16z.com/announcement/why-andreessen-horowitz-invested-in-foursquare/', null::text),
    (11, 'Marc Andreessen', 'Cofounder and General Partner', $qQ8s$Invest in distinctive strength that stands out—not merely a lack of weakness across team, product, and market.$qQ8s$, $qQ8$We talk a lot in our firm about — we have this concept — we say, “We invest in strength, not in lack of weakness.” And again, it’s one of these things that sounds obvious, but it’s proved to us to be a pretty big deal. So, there’s a lot of startups you’ll run into, or you probably have friends who are at these companies or know people at them, and it’s like, team’s good, product’s good, market seems good, they’re making some progress, they’ve got some customers, the customers are pretty happy. Okay. Where is that really gonna go, and where is it really gonna go? Because what’s spectacular about it, right? What’s the thing that’s gonna cause it to jump out from the other hundred, or other thousand companies where you can say the exact same thing?$qQ8$, date '2016-05-30', 'https://a16z.com/podcast/a16z-podcast-startups-and-pendulum-swings-through-ideas-time-fame-and-money/', null::text),
    (12, 'Marc Andreessen', 'Cofounder and General Partner', $qQ10s$Look for founder-market fit: the person born to do that idea.$qQ10s$, $qQ10$There’s another concept we call founder-market fit, which is — is the founder of a company — is that the person who’s born to do that idea? And so, that question we tend to defer to the founders, because we figured the really great founders are gonna figure that — like, part of what makes a founder great is they’re gonna figure that out. The other thing we found is that it’s very hard — we have ideas for companies we’d like to fund, but we try not to talk about them too much, because we don’t want somebody — we don’t want founders to pick up somebody else’s idea.$qQ10$, date '2016-05-30', 'https://a16z.com/podcast/a16z-podcast-startups-and-pendulum-swings-through-ideas-time-fame-and-money/', null::text)
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
