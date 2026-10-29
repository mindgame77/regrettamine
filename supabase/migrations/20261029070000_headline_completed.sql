-- A7.12 wins over A4.7 for a cut-off headline (Alex, 2026-10-28).
-- Same news link as a published news item, and the new headline is the full version of the published one
-- (published ends in '…' or '...', or is a prefix of the new one, and the new one is longer):
-- not a duplicate. The published headline is updated, the upload is Accepted, note 'headline completed'.
-- Any other same-link news item is still 'duplicate of a published news item'.

create or replace function public._entry_headline_completes(p_published text, p_new text)
 returns boolean language sql immutable set search_path = public as $$
  select coalesce(
    length(btrim(p_new)) > length(btrim(p_published))
    and (btrim(p_published) ~ '(…|\.\.\.)$' or left(btrim(p_new), length(btrim(p_published))) = btrim(p_published)),
    false);
$$;

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
                   in ('press', 'news', 'timeline') and i.url is not null
               and not public._entry_headline_completes(pi.headline, coalesce(i.f->>'headline', i.f->>'title'))) then
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

-- Updates cut-off published headlines to the full one. Returns how many were updated.
create or replace function public._entry_complete_headlines(p jsonb)
 returns integer language plpgsql security definer set search_path = public, extensions as $$
declare n integer;
begin
  with c as (
    select distinct on (pi.id) pi.id, left(btrim(coalesce(i.f->>'headline', i.f->>'title')), 400) h
      from public._checker_payload_items(p) i
      join public.press_items pi on public._checker_url_key(pi.url) = public._checker_url_key(i.url)
     where public._entry_section(i.section, case when i.n >= 1 then p->'records'->(i.n - 1)->>'field_path' end)
           in ('press', 'news', 'timeline') and i.url is not null
       and public._entry_headline_completes(pi.headline, coalesce(i.f->>'headline', i.f->>'title'))
     order by pi.id, length(coalesce(i.f->>'headline', i.f->>'title')) desc)
  update public.press_items pi set headline = c.h from c where pi.id = c.id and pi.headline is distinct from c.h;
  get diagnostics n = row_count;
  return n;
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

revoke all on function public._entry_headline_completes(text, text) from public, anon, authenticated;
revoke all on function public._entry_complete_headlines(jsonb) from public, anon, authenticated;
revoke all on function public._entry_duplicate(bigint, text, text, jsonb) from public, anon, authenticated;
revoke all on function bots.entry_check_trg() from public, anon, authenticated;
