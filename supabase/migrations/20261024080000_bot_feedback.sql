-- bot_feedback: messages returned in the `feedback` field of every research-ingest reply.
-- bot_id is a prefix (e.g. 'portal-night-bot' also matches 'portal-night-bot-2') or '*' for every bot.
-- Editable only by the service role (RLS on, no policies; anon/authenticated have no grants).
create table if not exists public.bot_feedback (
  id bigint generated always as identity primary key,
  bot_id text not null check (length(bot_id) between 1 and 100),
  message text not null check (length(message) between 1 and 2000),
  created_at timestamptz not null default now(),
  active boolean not null default true
);
alter table public.bot_feedback enable row level security;
revoke all on public.bot_feedback from anon, authenticated, public;
grant all on public.bot_feedback to service_role;
create index if not exists bot_feedback_active_idx on public.bot_feedback (active, created_at desc);

insert into public.bot_feedback (bot_id, message, created_at)
select * from (values
  ('*', 'Read and follow every message in this feedback field and in the feedback doc (feedback.doc_url) before your next claim. Newer messages override older ones.', timestamptz '2026-10-23 23:15:00-07'),
  ('portal-night-bot', 'Please fill every one of the 10 checks with a source URL; see the feedback doc', timestamptz '2026-10-23 23:15:01-07')
) v(bot_id, message, created_at)
where not exists (select 1 from public.bot_feedback);
