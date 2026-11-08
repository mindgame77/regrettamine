-- Assignment queue for v2 research. One row per firm waiting for research, linked only to v2_firms.
-- claim holds one free row for 6 hours. done finishes the caller's own hold. An expired hold can be claimed again.
-- v2_research_add_firm reads v2_firms only. v2_research_submit and publishing are not changed.
-- The v2 schema is not created by repo migrations. On a database without v2_firms (CI) this is a no-op.
-- Undo: supabase/rollbacks/20261108165320_v2_research_claim.sql
do $mig$
begin
  if to_regclass('public.v2_firms') is null
     or to_regclass('public.v2_bot_keys') is null
     or to_regclass('bots.ingest_keys') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;

  execute $ddl$
create table if not exists public.v2_research_assignments (
  firm_id bigint primary key references public.v2_firms(firm_id) on delete cascade,
  claimed_by text,
  claimed_at timestamptz,
  expires_at timestamptz,
  done_at timestamptz,
  constraint v2_research_assignments_hold_ck check (
    (claimed_by is null and claimed_at is null and expires_at is null)
    or (claimed_by is not null and claimed_at is not null and expires_at is not null)
  ),
  constraint v2_research_assignments_done_ck check (done_at is null or claimed_by is not null)
)
$ddl$;

  execute $idx$
create index if not exists v2_research_assignments_open
  on public.v2_research_assignments (firm_id)
  where done_at is null
$idx$;

  execute $rls$
alter table public.v2_research_assignments enable row level security;
revoke all on table public.v2_research_assignments from public, anon, authenticated
$rls$;

  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant select, insert, update, delete on table public.v2_research_assignments to service_role';
  end if;

  execute $cmt$
comment on table public.v2_research_assignments is 'One row per v2 firm waiting for research. Claim holds the row for 6 hours. Linked only to v2_firms.';
comment on column public.v2_research_assignments.claimed_by is 'bot_id from the ingest key that holds this firm.';
comment on column public.v2_research_assignments.claimed_at is 'When the current hold started.';
comment on column public.v2_research_assignments.expires_at is 'claimed_at plus 6 hours. After this the row can be claimed again until done_at is set.';
comment on column public.v2_research_assignments.done_at is 'When the holding bot finished. A finished row is not claimed again.'
$cmt$;

  execute $fn$
CREATE OR REPLACE FUNCTION public.v2_research_add_firm(p_key_id uuid, p_firm jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'bots'
 SET statement_timeout TO '30s'
 SET lock_timeout TO '5s'
AS $function$
DECLARE
  ik bots.ingest_keys;
  bk public.v2_bot_keys;
  bot text;
  nm text;
  web text;
  reg text;
  slg text;
  fid bigint;
BEGIN
  SELECT * INTO ik FROM bots.ingest_keys WHERE id = p_key_id AND active;
  IF NOT FOUND OR ik.bot_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'this key is not linked to a bot');
  END IF;
  bot := ik.bot_id;
  INSERT INTO public.v2_bot_keys (bot_name, key_hash) VALUES (bot, ik.key_hash)
    ON CONFLICT (bot_name) DO UPDATE SET key_hash = EXCLUDED.key_hash RETURNING * INTO bk;
  IF bk.frozen THEN
    RETURN jsonb_build_object('ok', false, 'bot_id', bot, 'error', format('Key frozen: %s, %s', coalesce(bk.freeze_reason, 'no reason'), to_char(bk.freeze_date AT TIME ZONE 'America/Los_Angeles', 'YYYY-MM-DD HH24:MI "PT"')));
  END IF;

  IF jsonb_typeof(p_firm) IS DISTINCT FROM 'object' THEN
    RETURN jsonb_build_object('ok', false, 'bot_id', bot, 'error', 'firm must be an object with name, website, registry_id');
  END IF;
  nm := btrim(coalesce(p_firm->>'name', ''));
  web := btrim(coalesce(p_firm->>'website', ''));
  reg := btrim(coalesce(p_firm->>'registry_id', ''));
  IF nm = '' OR web = '' OR reg = '' THEN
    RETURN jsonb_build_object('ok', false, 'bot_id', bot, 'error', 'firm needs name, website, and registry_id');
  END IF;
  IF length(nm) > 200 OR length(reg) > 200 THEN
    RETURN jsonb_build_object('ok', false, 'bot_id', bot, 'error', 'name and registry_id must be 200 characters or less');
  END IF;
  IF web !~* '^(https?://)?(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)+(:[0-9]+)?(/[^\s]*)?$' OR public.v2_url_never_website(web) THEN
    RETURN jsonb_build_object('ok', false, 'bot_id', bot, 'error', 'website is not a valid firm site');
  END IF;

  -- Existing firm on v2_firms only: registry value, the slug itself, the same website, then the name slug.
  SELECT r.firm_id INTO fid
    FROM public.v2_firm_registry_ids r
    JOIN public.v2_firms f ON f.firm_id = r.firm_id
   WHERE NOT r.archived AND NOT coalesce(f.archived, false) AND r.registry_value = reg
   ORDER BY r.is_current DESC, r.firm_id
   LIMIT 1;

  IF fid IS NULL THEN
    SELECT firm_id INTO fid FROM public.v2_firms
     WHERE NOT coalesce(archived, false) AND slug IN (reg, public._slugify(reg))
     ORDER BY firm_id
     LIMIT 1;
  END IF;

  IF fid IS NULL THEN
    SELECT firm_id INTO fid FROM public.v2_firms
     WHERE NOT coalesce(archived, false)
       AND website_url_norm IS NOT NULL
       AND website_url_norm = public.v2_norm_url(web)
     LIMIT 1;
  END IF;

  IF fid IS NULL AND public._slugify(nm) IS NOT NULL THEN
    SELECT firm_id INTO fid FROM public.v2_firms
     WHERE NOT coalesce(archived, false) AND slug = public._slugify(nm)
     LIMIT 1;
  END IF;

  IF fid IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'bot_id', bot, 'firm_id', fid, 'created', false,
      'slug', (SELECT slug FROM public.v2_firms WHERE firm_id = fid));
  END IF;

  slg := coalesce(public._slugify(nm), public._slugify(reg));
  IF slg IS NULL OR length(slg) > 200 THEN
    RETURN jsonb_build_object('ok', false, 'bot_id', bot, 'error', 'could not make a slug from name or registry_id');
  END IF;

  SELECT firm_id INTO fid FROM public.v2_firms WHERE slug = slg;
  IF fid IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'bot_id', bot, 'firm_id', fid, 'created', false, 'slug', slg);
  END IF;

  BEGIN
    INSERT INTO public.v2_firms (slug, display_name, website_url, firm_status)
    VALUES (slg, nm, web, 'Active')
    RETURNING firm_id INTO fid;
  EXCEPTION WHEN unique_violation THEN
    SELECT firm_id INTO fid FROM public.v2_firms
     WHERE slug = slg
        OR (website_url_norm = public.v2_norm_url(web) AND NOT coalesce(archived, false))
     ORDER BY firm_id
     LIMIT 1;
    IF fid IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'bot_id', bot, 'error', left(SQLERRM, 300));
    END IF;
    RETURN jsonb_build_object('ok', true, 'bot_id', bot, 'firm_id', fid, 'created', false,
      'slug', (SELECT slug FROM public.v2_firms WHERE firm_id = fid));
  END;

  RETURN jsonb_build_object('ok', true, 'bot_id', bot, 'firm_id', fid, 'created', true, 'slug', slg);
END
$function$;
$fn$;

  execute $claim$
CREATE OR REPLACE FUNCTION public.v2_research_claim(p_key_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'bots'
 SET statement_timeout TO '30s'
 SET lock_timeout TO '5s'
AS $function$
DECLARE
  ik bots.ingest_keys;
  bk public.v2_bot_keys;
  bot text;
  fid bigint;
  frm public.v2_firms;
BEGIN
  SELECT * INTO ik FROM bots.ingest_keys WHERE id = p_key_id AND active;
  IF NOT FOUND OR ik.bot_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'this key is not linked to a bot');
  END IF;
  bot := ik.bot_id;
  INSERT INTO public.v2_bot_keys (bot_name, key_hash) VALUES (bot, ik.key_hash)
    ON CONFLICT (bot_name) DO UPDATE SET key_hash = EXCLUDED.key_hash RETURNING * INTO bk;
  IF bk.frozen THEN
    RETURN jsonb_build_object('ok', false, 'bot_id', bot, 'error', format('Key frozen: %s, %s', coalesce(bk.freeze_reason, 'no reason'), to_char(bk.freeze_date AT TIME ZONE 'America/Los_Angeles', 'YYYY-MM-DD HH24:MI "PT"')));
  END IF;

  fid := null;
  WITH picked AS (
    SELECT q.firm_id
      FROM public.v2_research_assignments q
      JOIN public.v2_firms f ON f.firm_id = q.firm_id
     WHERE q.done_at IS NULL
       AND NOT coalesce(f.archived, false)
       AND (
         q.claimed_by IS NULL
         OR coalesce(q.expires_at, q.claimed_at + interval '6 hours') <= now()
       )
     ORDER BY q.firm_id
     FOR UPDATE OF q SKIP LOCKED
     LIMIT 1
  )
  UPDATE public.v2_research_assignments a
     SET claimed_by = bot,
         claimed_at = now(),
         expires_at = now() + interval '6 hours'
    FROM picked
   WHERE a.firm_id = picked.firm_id
  RETURNING a.firm_id INTO fid;

  IF fid IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'bot_id', bot, 'none_left', true);
  END IF;

  SELECT * INTO frm FROM public.v2_firms WHERE firm_id = fid;
  RETURN jsonb_build_object(
    'ok', true,
    'bot_id', bot,
    'firm_id', frm.firm_id,
    'slug', frm.slug,
    'name', frm.display_name,
    'website', frm.website_url);
END
$function$;
$claim$;

  execute $done$
CREATE OR REPLACE FUNCTION public.v2_research_done(p_key_id uuid, p_firm_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'bots'
 SET statement_timeout TO '30s'
 SET lock_timeout TO '5s'
AS $function$
DECLARE
  ik bots.ingest_keys;
  bk public.v2_bot_keys;
  bot text;
  rec public.v2_research_assignments;
BEGIN
  SELECT * INTO ik FROM bots.ingest_keys WHERE id = p_key_id AND active;
  IF NOT FOUND OR ik.bot_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'this key is not linked to a bot');
  END IF;
  bot := ik.bot_id;
  INSERT INTO public.v2_bot_keys (bot_name, key_hash) VALUES (bot, ik.key_hash)
    ON CONFLICT (bot_name) DO UPDATE SET key_hash = EXCLUDED.key_hash RETURNING * INTO bk;
  IF bk.frozen THEN
    RETURN jsonb_build_object('ok', false, 'bot_id', bot, 'error', format('Key frozen: %s, %s', coalesce(bk.freeze_reason, 'no reason'), to_char(bk.freeze_date AT TIME ZONE 'America/Los_Angeles', 'YYYY-MM-DD HH24:MI "PT"')));
  END IF;

  IF p_firm_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'bot_id', bot, 'error', 'firm_id is required');
  END IF;

  SELECT * INTO rec
    FROM public.v2_research_assignments
   WHERE firm_id = p_firm_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'bot_id', bot, 'error', 'firm is not in the assignment queue');
  END IF;
  IF rec.claimed_by IS DISTINCT FROM bot THEN
    RETURN jsonb_build_object('ok', false, 'bot_id', bot, 'error', 'this firm is not assigned to this bot');
  END IF;
  IF rec.done_at IS NULL THEN
    UPDATE public.v2_research_assignments
       SET done_at = now()
     WHERE firm_id = p_firm_id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'bot_id', bot, 'firm_id', p_firm_id, 'done', true);
END
$function$;
$done$;

  execute 'revoke all on function public.v2_research_add_firm(uuid, jsonb) from public, anon, authenticated';
  execute 'revoke all on function public.v2_research_claim(uuid) from public, anon, authenticated';
  execute 'revoke all on function public.v2_research_done(uuid, bigint) from public, anon, authenticated';
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.v2_research_add_firm(uuid, jsonb) to service_role';
    execute 'grant execute on function public.v2_research_claim(uuid) to service_role';
    execute 'grant execute on function public.v2_research_done(uuid, bigint) to service_role';
  end if;
end
$mig$;
