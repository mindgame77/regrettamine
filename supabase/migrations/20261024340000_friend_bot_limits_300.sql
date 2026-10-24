-- Friend's bot (portal-night-bot*) key: raise rate limit to 300 req/min (approved by Alex).
update public.ingest_keys set rate_limit_per_min = 300 where name = 'external-friend-2026-10-23';

insert into public.bot_feedback (bot_id, message, active)
values ('portal-night-bot',
 'Limits raised: you may claim up to 300 firms per request (count up to 300) and run parallel copies. Only claim what you can finish within 6 hours; unfinished claims are released after 6 hours. Rate limit is 300 requests/min; on a 429, wait 60 seconds and retry.',
 true);
