-- Data for News as one list. Proposed, not applied to the live database.
-- 1. Copy the General Catalyst Bonatsos TechCrunch story from vc_source_facts
--    into press_items / press_item_firms as not_checked. The vc_source_facts row stays.
--    Two other notes on the same URL are needs_proof and say different things.
--    They are not copied (docs/CONFLICT_RULE.md).
-- 2. Record one check for each timeline event on the 10 Experiment Lab firms.
--    source_url is a page that was opened. headline_match is a paywalled or title match.
--    An event with no confirmed source stays not_checked and keeps source_url empty.
--    No timeline row is deleted. No URL was invented.
-- Checked on 2026-10-27. 45 checked_correct, 0 checked_wrong, 10 not_checked.
-- plugandplay has no timeline rows.

alter table public.press_item_firms disable trigger firm_page_cache_inv;

insert into public.press_items (
  publisher, domain, url, published_on, published_label, headline, snippet,
  data_status, retrieved_at, source_system, external_id
)
select
  'TechCrunch',
  'techcrunch.com',
  'https://techcrunch.com/2026/01/07/discord-and-mercor-investor-niko-bonatsos-departs-general-catalyst-plans-new-vc-firm/',
  date '2026-01-07',
  '2026-01-07',
  'Discord and Mercor investor Niko Bonatsos departs General Catalyst, plans new VC firm',
  'Left General Catalyst 2026-01 after leading seed strategy; plans new early-stage firm',
  'real',
  now(),
  'vc_source_facts-copy',
  '734e8c24-7781-5169-8f93-2aa79085dc54'
where exists (select 1 from public.firms f where f.slug = 'generalcatalyst' and f.deleted_at is null)
  and not exists (
    select 1 from public.press_items pi
    where pi.source_system = 'vc_source_facts-copy'
      and pi.external_id = '734e8c24-7781-5169-8f93-2aa79085dc54'
  )
  and not exists (
    select 1 from public.press_items pi
    where lower(regexp_replace(regexp_replace(split_part(split_part(btrim(pi.url), '#', 1), '?', 1), '^https?://(www\.)?', '', 'i'), '/+$', ''))
      = 'techcrunch.com/2026/01/07/discord-and-mercor-investor-niko-bonatsos-departs-general-catalyst-plans-new-vc-firm'
  );

insert into public.press_item_firms (press_item_id, firm_id, sort_order, check_mark, checked_source)
select
  pi.id,
  f.id,
  coalesce((select max(pf.sort_order) from public.press_item_firms pf where pf.firm_id = f.id), -1) + 1,
  'not_checked',
  'vc_source_facts-copy'
from public.press_items pi
join public.firms f on f.slug = 'generalcatalyst' and f.deleted_at is null
where pi.source_system = 'vc_source_facts-copy'
  and pi.external_id = '734e8c24-7781-5169-8f93-2aa79085dc54'
  and not exists (
    select 1 from public.press_item_firms pf
    where pf.press_item_id = pi.id and pf.firm_id = f.id
  );

alter table public.press_item_firms enable trigger firm_page_cache_inv;

update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://a16z.com/about/', check_note = null, last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = 'b068edb2-ea82-5442-5d0b-db50d86410eb'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://storage.courtlistener.com/recap/gov.uscourts.cand.404947/gov.uscourts.cand.404947.249.0.pdf', check_note = null, last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = '9851bbc5-7303-5d9b-8d1d-0233821a25be'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://techcrunch.com/2025/11/03/a16z-pauses-its-famed-txo-fund-for-underserved-founders-lays-off-staff/', check_note = 'headline_match', last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = '6df93a03-4f9b-5d2a-a407-eb9da095c9ba'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://a16z.com/why-did-we-raise-15b/', check_note = 'headline_match', last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = 'e1458eb0-90ea-5071-9de0-86055067fa05'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://courts.delaware.gov/Opinions/Download.aspx?id=391020', check_note = null, last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = '2a41e2b6-faaf-5da9-9847-7e0bffc35d2b'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://www.formds.com/investment-advisers/andreessen-horowitz', check_note = null, last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = '5a43323d-121d-5214-a0c5-3935fa7431f6'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://www.axios.com/2026/06/04/anne-neuberger-andreessen-horowitz', check_note = 'headline_match', last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = '86a20884-25b6-5277-8624-484e5eb3510e'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://www.reuters.com/legal/legalindustry/andreessen-horowitz-focus-doj-probe-over-board-directors-bloomberg-news-reports-2026-08-17/', check_note = 'headline_match', last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = 'ce1e039d-17f2-42cd-208f-840facce6ec4'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://techcrunch.com/2026/08/18/dojs-probe-into-andreessen-horowitz-over-board-seats-baffles-vcs/', check_note = 'headline_match', last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = 'c50b45de-ac84-5dd6-8a61-5ae495456822'::uuid;
update public.timeline_events set check_mark = 'not_checked', source_url = null, check_note = null
where id = '20644c24-ac74-504c-836d-13a2bc4c565f'::uuid;
update public.timeline_events set check_mark = 'not_checked', source_url = null, check_note = null
where id = '5223e4b6-5c65-54e5-8f3f-ca4ba3009c54'::uuid;
update public.timeline_events set check_mark = 'not_checked', source_url = null, check_note = null
where id = '65cfa291-8169-7c66-c9be-4d17daa1a1d7'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://www.accel.com/news/our-commitment-to-exceptional-teams-across-europe-and-israel', check_note = null, last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = '7419434a-1176-f67e-e748-508e58139869'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://api.gleif.org/api/v1/lei-records/213800KC5TYZDXPQGQ36', check_note = null, last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = '06f41a27-d1e1-8e37-8ebc-28ad87f3c566'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://techcrunch.com/2010/11/22/accel-partners-fund-ix-facebook-extraordinary/', check_note = null, last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = 'fdcb3fc0-6a78-2d23-3b0e-2a7507dfa590'::uuid;
update public.timeline_events set check_mark = 'not_checked', source_url = null, check_note = null
where id = 'e0801848-9372-a043-8842-6834c113c83b'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://techcrunch.com/2010/07/14/atlassian-accel-60-million/', check_note = 'headline_match', last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = '1de1ecd0-ea5a-abfd-2883-56e1a45fbd4d'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://www.accel.com/news/freshworks-chennai-a-decade-of-aspirations-and-accomplishments', check_note = null, last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = 'db699246-dff1-8da5-6242-2e3b7dfae981'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://nvidianews.nvidia.com/news/nvidia-completes-acquisition-of-icera-a-leader-in-wireless-modem-rf-technology-6622906', check_note = 'headline_match', last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = '917922ec-1ba4-cd60-aa93-95d477589eef'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://www.sec.gov/Archives/edgar/data/1312928/000119312513228969/d540491d8k.htm', check_note = null, last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = 'a829ce1b-6ba0-e5c5-30f6-e15f04458b51'::uuid;
update public.timeline_events set check_mark = 'not_checked', source_url = null, check_note = null
where id = '285b5592-b5e7-57a7-b4b7-9caa98bcd59c'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://www.courtlistener.com/docket/16222193/pirani-v-slack-technologies-inc/', check_note = null, last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = 'd24a7249-5b72-5ac5-ff05-7ba1ca4da65f'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://www.accel.com/news/freshworks-chennai-a-decade-of-aspirations-and-accomplishments', check_note = null, last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = '7eaa4f1f-a524-e32a-f9d5-d63c9b0b9fe1'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://techcrunch.com/2022/06/21/accel-new-4-billion-fund/', check_note = 'headline_match', last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = '787593c5-98ce-5377-c022-d7a6b4fdc7cd'::uuid;
update public.timeline_events set check_mark = 'not_checked', source_url = null, check_note = null
where id = 'cf3acad1-adab-5cfa-a556-baf245342b99'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://www.sec.gov/Archives/edgar/data/2020727/000202072724000001/0002020727-24-000001.txt', check_note = null, last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = 'd0ccc5f1-ffaf-edd9-e0fc-d3cf729a43d9'::uuid;
update public.timeline_events set check_mark = 'not_checked', source_url = null, check_note = null
where id = '66b8d6a6-b1e2-4361-eef0-269f9659b656'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://www.accel.com/news/fueling-the-future-announcing-our-viii-fund-for-indias-boldest-founders', check_note = null, last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = 'd7c3a08d-8f55-dc37-e5e0-55b3c4e8269e'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://cdn.ca9.uscourts.gov/datastore/opinions/2025/02/10/20-16419.pdf', check_note = null, last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = '21289861-e39b-ba4d-d8bc-a334527e145c'::uuid;
update public.timeline_events set check_mark = 'not_checked', source_url = null, check_note = null
where id = 'd38046d5-9a9b-51d3-9d16-8f5989018527'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://www.bloomberg.com/news/articles/2026-04-15/anthropic-cursor-backer-accel-raises-5-billion-for-big-ai-bets', check_note = 'headline_match', last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = 'c924dbc7-2d00-2da2-ca26-9928c1cbe226'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://www.accel.com/news/our-enduring-commitment-to-investing-at-the-earliest-stages', check_note = null, last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = 'a9a5ee09-0c50-73b3-ec5c-d55d9ea0373c'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://tech.eu/2026/09/11/luca-bocchio-joins-balderton-as-partner-after-more-than-a-decade-in-european-vc/', check_note = null, last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = '4dc0ab51-e29e-760b-a4eb-8e8cc0c5c5ef'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://techcrunch.com/2026/03/11/vc-mega-funds-are-back-with-general-catalyst-spark-rumored-to-be-raising-billions/', check_note = 'headline_match', last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = 'c62d2829-9c02-f292-b5a4-74180a1923cf'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://www.sec.gov/Archives/edgar/data/1834584/000114036126017102/ny20063059x1_def14a.htm', check_note = null, last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = '42cf6b95-2ac5-a0f0-e14f-785c7cafff99'::uuid;
update public.timeline_events set check_mark = 'not_checked', source_url = null, check_note = null
where id = '0d7f014d-2410-5538-a2d6-69cd29893c6a'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://www.ajupress.com/view/20260310073122199', check_note = 'headline_match', last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = '6f3df384-727c-44de-448f-9788ff976f58'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://www.mk.co.kr/en/society/12024467', check_note = null, last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = '61a61c59-43e0-d5fe-bd4f-cc53ec4becc0'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://techcrunch.com/2013/01/25/rabois-left-square-over-sexual-harassment-claim/', check_note = 'headline_match', last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = '6ca59c9c-5a96-5ff4-ae53-46386f5a7417'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://courts.ms.gov/Images/Opinions/CO137805.pdf', check_note = null, last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = '2d102490-4932-55c6-9b42-a769dabc5f78'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://www.sfexaminer.com/news/climate/martins-beach-case-pauses-for-vinod-khosla-settlement-talks/article_2d71f6e6-2b72-462f-bf9e-754899a6b7bd.html', check_note = null, last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = 'be5166e4-21ad-5924-a49e-3dd8a2f4f7d5'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://www.sec.gov/Archives/edgar/data/1846069/000184606926000098/R13.htm', check_note = null, last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = 'd3f45f4e-cc9f-55a3-b03c-5a00cc79d821'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://timesofindia.indiatimes.com/technology/tech-news/vinod-khosla-give-230-word-long-reply-to-elon-musk-says-instead-of-bringing-your-family-try-not-/articleshow/127761013.cms', check_note = 'headline_match', last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = '69fea6ae-f271-5a23-90d2-2a4d13ac7f81'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://www.bloomberg.com/news/articles/2026-07-23/khosla-ventures-in-talks-to-raise-5-5-billion-in-new-funds', check_note = 'headline_match', last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = '22289f39-97d8-3927-7b31-21f8909c2f33'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://techcrunch.com/2026/09/24/lightspeed-targets-250m-for-new-india-fund-focusing-on-early-stage-ai/', check_note = 'headline_match', last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = '0ef46963-65c1-ad88-439c-c9454b4aafdd'::uuid;
update public.timeline_events set check_mark = 'not_checked', source_url = null, check_note = null
where id = 'd28aa658-9ba1-5c97-9582-2647d9134fcb'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://storage.courtlistener.com/recap/gov.uscourts.nysd.510220/gov.uscourts.nysd.510220.110.0.pdf', check_note = null, last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = 'f2dd8968-9d71-563b-8b35-b812c3c0e717'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://www.sec.gov/files/litigation/admin/2021/ia-5912.pdf', check_note = null, last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = '5921c7f9-bdcf-5bb5-a6e0-a8643aab2ebe'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://www.sec.gov/files/litigation/admin/2021/ia-5912.pdf', check_note = null, last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = 'fc3ce660-e7a2-52f6-9b4b-b42fe01e2028'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://www.bloomberg.com/news/articles/2026-02-10/mckinsey-hands-over-its-20-billion-investment-arm-to-neuberger', check_note = 'headline_match', last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = 'b0e2ec37-ba5b-f565-e7f0-1049778ef699'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://techcrunch.com/2025/11/04/sequoia-names-alfred-lin-and-pat-grady-as-new-co-stewards-as-roelof-botha-steps-down/', check_note = 'headline_match', last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = '2e70ea46-cfc7-ae59-21d3-667aadfb9eb2'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://storage.courtlistener.com/recap/gov.uscourts.flmd.414572/gov.uscourts.flmd.414572.24.0_1.pdf', check_note = null, last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = 'be323e0e-22a3-516a-9bd3-3905398b67ba'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://techcrunch.com/2023/09/20/why-is-y-combinator-so-defensive-lately/', check_note = null, last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = 'e4e13b68-d703-59da-af0f-a1cd73d1cfc3'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://techcrunch.com/2024/01/28/y-combinator-president-garry-tan-publishes-a-menacing-tweet-before-deleting-it-apologizing-die-slow-motherfckers/', check_note = 'headline_match', last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = '608e6f54-3554-5232-abc7-f2378d4904eb'::uuid;
update public.timeline_events set check_mark = 'checked_correct', source_url = 'https://www.harmonyoswald.com/_files/ugd/d44885_3577ab1f90ae4138ad60dca84c3449c4.pdf', check_note = null, last_checked_at = timestamptz '2026-10-27 21:45:00+00'
where id = 'be2987e0-877f-53d0-b95d-311d71dfe44f'::uuid;
