-- Each friend bot can read its own entry-check results (A4.6 changed; Alex, 2026-10-28).
-- Two server-only readers for the research-ingest Edge Function. Nothing else changes:
-- no table, column, trigger, policy or existing function is altered.
--   public.research_entry_result(submission id)  -> the entry check of the row just uploaded (upload response)
--   public.research_my_results(key id, days, n)  -> that key's bot's own rows, last 30 days, at most 30
-- The bot comes from bots.ingest_keys.bot_id of the authenticated key (ingest_auth returns key_id), never from the
-- request body. A key with no bot_id, or an inactive key, gets an error and no rows.
-- Grants follow A14.6: fixed search_path, no EXECUTE for public/anon/authenticated; service_role only.
-- Rollback: supabase/rollbacks/20261029093000_bot_own_results.sql

create or replace function public.research_entry_result(p_sub bigint)
 returns jsonb language sql stable security definer set search_path = bots, public as $$
  select coalesce((select jsonb_build_object('entry_check', s.entry_check, 'entry_notes', to_jsonb(s.entry_notes),
                                             'entry_check_at', s.entry_check_at)
                     from bots.research_submissions s where s.id = p_sub),
                  jsonb_build_object('entry_check', null, 'entry_notes', null, 'entry_check_at', null));
$$;

create or replace function public.research_my_results(p_key uuid, p_days int default 30, p_limit int default 30)
 returns jsonb language plpgsql stable security definer set search_path = bots, public as $$
declare v_bot text; d int := least(greatest(coalesce(p_days, 30), 1), 30); n int := least(greatest(coalesce(p_limit, 30), 1), 30);
begin
  select k.bot_id into v_bot from bots.ingest_keys k where k.id = p_key and k.active;
  if nullif(btrim(v_bot), '') is null then
    return jsonb_build_object('ok', false, 'error', 'this key is not linked to a bot; ask Alex to link it');
  end if;
  return jsonb_build_object('ok', true, 'bot_id', v_bot, 'days', d, 'results', coalesce((
    select jsonb_agg(jsonb_build_object('submission_id', s.id, 'registry_id', s.registry_id, 'received_at', s.received_at,
             'entry_check', s.entry_check, 'entry_notes', to_jsonb(s.entry_notes), 'entry_check_at', s.entry_check_at)
           order by s.received_at desc, s.id desc)
      from (select * from bots.research_submissions x
             where x.bot_id = v_bot and x.received_at > now() - make_interval(days => d)
             order by x.received_at desc, x.id desc limit n) s), '[]'::jsonb));
end $$;

revoke all on function public.research_entry_result(bigint) from public, anon, authenticated;
revoke all on function public.research_my_results(uuid, int, int) from public, anon, authenticated;
grant execute on function public.research_entry_result(bigint) to service_role;
grant execute on function public.research_my_results(uuid, int, int) to service_role;
