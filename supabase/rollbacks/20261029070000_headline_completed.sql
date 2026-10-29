-- Rollback: news duplicate is always rejected again; no headline completion (pre-A7.12 restore).
drop function if exists public._entry_complete_headlines(jsonb);
create or replace function public._entry_duplicate(p_id bigint, p_registry text, p_bot text, p jsonb)
 returns text language plpgsql stable security definer set search_path = public, extensions as $$
declare k text := public._door_key(p_registry, p);
begin
  if exists (select 1 from bots.research_submissions s
              where s.id is distinct from p_id
                and coalesce(s.door_key, public._door_key(s.registry_id, s.payload)) = k) then
    return 'duplicate of an earlier upload';
  end if;
  if exists (select 1 from public._checker_payload_items(p) i
              join public.press_items pi on public._checker_url_key(pi.url) = public._checker_url_key(i.url)
             where public._entry_section(i.section, case when i.n >= 1 then p->'records'->(i.n - 1)->>'field_path' end)
                   in ('press', 'news', 'timeline') and i.url is not null) then
    return 'duplicate of a published news item';
  end if;
  if exists (select 1 from public._checker_payload_items(p) i
              where i.url is not null
              group by i.section, public._checker_url_key(i.url), coalesce(i.f->>'value', i.f::text)
             having count(*) > 1) then
    return 'duplicate items inside the upload';
  end if;
  return null;
end $$;

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
  exception when others then
    new.entry_check := 'Rejected: entry check error';  -- never block the upload itself
  end;
  new.entry_check_at := now();
  new.entry_link_open_pending := (new.entry_check = 'Accepted');
  return new;
end $$;

drop trigger if exists aa_entry_check on bots.research_submissions;
create trigger aa_entry_check before insert on bots.research_submissions
  for each row execute function bots.entry_check_trg();
drop function if exists public._entry_headline_completes(text, text);
revoke all on function public._entry_duplicate(bigint, text, text, jsonb) from public, anon, authenticated;
revoke all on function bots.entry_check_trg() from public, anon, authenticated;
