-- UI strings with explicit text variants. NOT APPLIED YET (pending Alex's approval).
-- One row per (key, variant, locale). The variant names the condition that selects the text;
-- `condition` documents it in words. Bundled fallback: src/js/strings.js (RS.load falls back on any error).

create table public.ui_strings (
  id bigint generated always as identity primary key,
  key text not null check (key ~ '^[a-z0-9_]+(\.[a-z0-9_]+)+$'),
  variant text not null default 'default' check (variant ~ '^[a-z0-9_]+$'),
  condition text not null default 'always',
  text text not null,
  locale text not null default 'en',
  note text,
  status text not null default 'live' check (status in ('live', 'planned', 'retired')),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  unique (key, variant, locale)
);

create index ui_strings_key on public.ui_strings (key);

alter table public.ui_strings enable row level security;

-- Anyone can read copy; only the service role writes (no insert/update/delete policy).
create policy ui_strings_read on public.ui_strings for select to anon, authenticated using (true);

create or replace function public.ui_strings_touch() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;
create trigger ui_strings_touch before update on public.ui_strings
  for each row execute function public.ui_strings_touch();

-- Seed from src/js/strings.js (generated). Keep in sync until the loader is wired on every page.
insert into public.ui_strings (key, variant, condition, text, locale, note, status) values
  ('brand.name', 'default', 'always', 'Regretamin', 'en', 'Product name shown to users (logo alt text, titles, copy). The logo itself is assets/logo/lockup-*.svg. Domain stays regretamine.com.', 'live'),
  ('brand.domain', 'default', 'always', 'regretamine.com', 'en', 'Public domain. Not a brand name; keep the e.', 'live'),
  ('scoring.step3.body', 'default', 'always', '0 to 100, higher means fewer red flags in the sources we checked, from published rules.', 'en', 'Scoring page, how-it-works step 03.', 'live'),
  ('report.sentiment.label', 'pos', 'item.sentiment = pos', 'Positive', 'en', 'Public tab sentiment tag and filter.', 'live'),
  ('report.sentiment.label', 'neu', 'item.sentiment = neu', 'Neutral', 'en', 'Public tab sentiment tag and filter.', 'live'),
  ('report.sentiment.label', 'neg', 'item.sentiment = neg', 'Negative', 'en', 'Public tab sentiment tag and filter.', 'live'),
  ('score.band', 'very_low', 'score 90-100', 'Very low risk', 'en', 'Risk band label from the score (fund list, report).', 'live'),
  ('score.band', 'low', 'score 75-89', 'Low risk', 'en', 'Risk band label from the score (fund list, report).', 'live'),
  ('score.band', 'moderate', 'score 50-74', 'Moderate', 'en', 'Risk band label from the score (fund list, report).', 'live'),
  ('score.band', 'elevated', 'score 25-49', 'Elevated', 'en', 'Risk band label from the score (fund list, report).', 'live'),
  ('score.band', 'high', 'score 0-24', 'High', 'en', 'Risk band label from the score (fund list, report).', 'live'),
  ('score.band_short', 'very_low', 'score 90-100', 'Very low', 'en', 'Short band label in filters.', 'live'),
  ('score.band_short', 'low', 'score 75-89', 'Low', 'en', 'Short band label in filters.', 'live'),
  ('score.band_short', 'moderate', 'score 50-74', 'Moderate', 'en', 'Short band label in filters.', 'live'),
  ('score.band_short', 'elevated', 'score 25-49', 'Elevated', 'en', 'Short band label in filters.', 'live'),
  ('score.band_short', 'high', 'score 0-24', 'High', 'en', 'Short band label in filters.', 'live'),
  ('auth.heading', 'gate', 'anon hit the free report limit', 'Two funds in.<br>Don''t <span class="mark">regret the third</span>.', 'en', 'Auth/gate modal heading, one per modal mode (HTML).', 'live'),
  ('auth.heading', 'page', '/login/ page', 'Check first.<br><span class="mark">Sign second</span>.', 'en', 'Auth/gate modal heading, one per modal mode (HTML).', 'live'),
  ('auth.heading', 'list', 'anon opened the full fund list', 'Log in to see<br><span class="mark">all <span id="listN"></span> funds</span>.', 'en', 'Auth/gate modal heading, one per modal mode (HTML).', 'live'),
  ('auth.heading', 'pay', 'free account hit its report limit', 'You''ve checked 7 funds.<br>The 8th could be the one you <span class="mark">regret</span>.', 'en', 'Auth/gate modal heading, one per modal mode (HTML).', 'live'),
  ('auth.heading', 'plans', 'plans placeholder', 'Plans', 'en', 'Auth/gate modal heading, one per modal mode (HTML).', 'live'),
  ('auth.heading', 'confirm', 'signed up, email not confirmed', 'Confirm your email.', 'en', 'Auth/gate modal heading, one per modal mode (HTML).', 'live'),
  ('auth.heading', 'forgot', 'forgot password', 'Reset your password.', 'en', 'Auth/gate modal heading, one per modal mode (HTML).', 'live'),
  ('auth.heading', 'reset', 'recovery link opened', 'Choose a new password.', 'en', 'Auth/gate modal heading, one per modal mode (HTML).', 'live'),
  ('auth.sub', 'list', 'anon opened the full fund list', 'Free account. No card.', 'en', 'Auth/gate modal subline per mode.', 'live'),
  ('auth.sub', 'gate', 'anon hit the free report limit', 'A free account unlocks 5 more reports. No card.', 'en', 'Auth/gate modal subline per mode.', 'live'),
  ('auth.sub', 'pay', 'free account hit its report limit', 'Unlimited reports and alerts when a fund you''re talking to gets sued.', 'en', 'Auth/gate modal subline per mode.', 'live'),
  ('auth.sub', 'plans', 'plans placeholder', 'Unlimited reports, when pricing is ready. Nothing to pay today.', 'en', 'Auth/gate modal subline per mode.', 'live'),
  ('auth.sub', 'confirm', 'signed up, email not confirmed', 'The extra 5 reports open after you confirm. We sent the link to your inbox.', 'en', 'Auth/gate modal subline per mode.', 'live'),
  ('auth.sub', 'forgot', 'forgot password', 'We''ll email you a link to set a new password.', 'en', 'Auth/gate modal subline per mode.', 'live'),
  ('auth.sub', 'reset', 'recovery link opened', 'Use at least 6 characters.', 'en', 'Auth/gate modal subline per mode.', 'live'),
  ('auth.submit', 'signup', 'mode signup', 'Create account', 'en', 'Auth form submit button per mode.', 'live'),
  ('auth.submit', 'login', 'mode login', 'Log in', 'en', 'Auth form submit button per mode.', 'live'),
  ('auth.submit', 'forgot', 'mode forgot', 'Send reset link', 'en', 'Auth form submit button per mode.', 'live'),
  ('auth.submit', 'reset', 'mode reset', 'Update password', 'en', 'Auth form submit button per mode.', 'live'),
  ('plans.start_cta', 'monthly', 'monthly plan', 'Start monthly', 'en', 'Plans page checkout button per plan.', 'live'),
  ('plans.start_cta', 'annual', 'annual plan', 'Start annual', 'en', 'Plans page checkout button per plan.', 'live'),
  ('plans.start_cta', 'test', 'test purchase (admin)', '$1 test purchase', 'en', 'Plans page checkout button per plan.', 'live'),
  ('verdict.headline', 'clear', 'all sources clear', 'No red flags found in these sources', 'en', 'Trust-check verdict pill/headline (new flow, not wired yet). Never say ''safe''.', 'planned'),
  ('verdict.headline', 'review', '>=1 review, 0 flags', 'Mostly clear · {n} to review', 'en', 'Trust-check verdict pill/headline (new flow, not wired yet). Never say ''safe''.', 'planned'),
  ('verdict.headline', 'flag', '>=1 flag', '{n} red flags found', 'en', 'Trust-check verdict pill/headline (new flow, not wired yet). Never say ''safe''.', 'planned'),
  ('verdict.headline', 'no_data', 'no source returned data', 'No data yet', 'en', 'Trust-check verdict pill/headline (new flow, not wired yet). Never say ''safe''.', 'planned'),
  ('check.status', 'clear', 'source returned no match', '✓ Clear', 'en', 'Databases checklist row status.', 'planned'),
  ('check.status', 'review', 'match needs review', '! Review', 'en', 'Databases checklist row status.', 'planned'),
  ('check.status', 'flag', 'confirmed adverse record', '✕ Flag', 'en', 'Databases checklist row status.', 'planned'),
  ('check.status', 'no_data', 'source not checked or failed', 'No data yet', 'en', 'Databases checklist row status.', 'planned'),
  ('check.status', 'queued', 'firm not researched, worker queued', '… Queued', 'en', 'Databases checklist row status.', 'planned'),
  ('unlock.cta', 'logged_out', 'no session', 'Unlock full report', 'en', 'Full dossier button.', 'planned'),
  ('unlock.cta', 'free', 'free account', '$49/mo · Unlock all dossiers', 'en', 'Full dossier button.', 'planned'),
  ('unlock.cta', 'paid', 'active subscription', 'Open full report', 'en', 'Full dossier button.', 'planned')
on conflict (key, variant, locale) do nothing;
