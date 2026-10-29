-- Rollback: headline completed at the entry check again (as in 20261029070000), gate without it.
create or replace function bots.entry_check_trg()
 returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare fx jsonb;
begin
  perform bots.apply_limits();
  begin
    -- Duplicate key from the payload as sent, so an exact copy still matches after the fix-ups below.
    new.door_key := coalesce(new.door_key, public._door_key(new.registry_id, new.payload));
    new.entry_check := public._entry_check(new.id, new.registry_id, new.bot_id, new.payload);
    fx := public._entry_fix_payload(new.payload);
    new.payload := fx->'payload';
    new.entry_notes := nullif(array(select jsonb_array_elements_text(fx->'notes')), '{}');
    -- A7.12: an Accepted upload that completes a cut-off published headline updates it.
    if new.entry_check = 'Accepted' and public._entry_complete_headlines(new.payload) > 0 then
      new.entry_notes := coalesce(new.entry_notes, '{}') || 'headline completed'::text;
    end if;
  exception when others then
    new.entry_check := 'Rejected: entry check error';  -- never block the upload itself
  end;
  new.entry_check_at := now();
  new.entry_link_open_pending := (new.entry_check = 'Accepted');
  return new;
end $$;

create or replace function public._checker_entry_gate(p_id bigint, p_probes jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = bots, public, extensions
as $$
declare sub bots.research_submissions; probes jsonb; u text; ok boolean; unknown boolean := false;
begin
  select * into sub from research_submissions where id = p_id;
  if sub.id is null then return jsonb_build_object('ran', false, 'reason', 'no such row'); end if;
  if sub.entry_check is distinct from 'Accepted' then
    return jsonb_build_object('ran', false, 'reason', 'entry check not Accepted', 'entry_check', sub.entry_check);
  end if;
  if not coalesce(sub.entry_link_open_pending, false) then return null; end if;
  probes := coalesce(p_probes, sub.payload->'probes');
  for u in select distinct it.url from public._checker_payload_items(sub.payload) it where it.url is not null loop
    ok := public._checker_link_opens(u, probes);
    if ok is null then
      unknown := true;
    elsif not ok then
      update research_submissions
         set entry_check = 'Rejected: link does not open', entry_check_at = now(), entry_link_open_pending = false
       where id = p_id;
      return jsonb_build_object('ran', false, 'reason', 'link does not open', 'url', u);
    end if;
  end loop;
  if unknown then return jsonb_build_object('ran', false, 'reason', 'link not opened yet'); end if;
  update research_submissions set entry_link_open_pending = false where id = p_id;
  return null;
end $$;

revoke all on function bots.entry_check_trg() from public, anon, authenticated;
revoke all on function public._checker_entry_gate(bigint, jsonb) from public, anon, authenticated;
grant execute on function public._checker_entry_gate(bigint, jsonb) to service_role;
