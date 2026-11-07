-- add_firm: one idempotent insert into v2_firms for the v2 research door.
-- Called by research-ingest-v2 action add_firm. Does not publish facts and does not change v2_research_submit.
-- The v2 schema is not created by repo migrations. On a database without v2_firms (CI) this is a no-op.
-- Undo: supabase/rollbacks/20261107180000_v2_research_add_firm.sql
do $mig$
begin
  if to_regclass('public.v2_firms') is null
     or to_regclass('public.v2_bot_keys') is null
     or to_regclass('bots.ingest_keys') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;

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

  -- Existing firm: registry value, the v1 registry id's slug, the slug itself, the same website, then the name slug.
  SELECT r.firm_id INTO fid
    FROM public.v2_firm_registry_ids r
    JOIN public.v2_firms f ON f.firm_id = r.firm_id
   WHERE NOT r.archived AND NOT coalesce(f.archived, false) AND r.registry_value = reg
   ORDER BY r.is_current DESC, r.firm_id
   LIMIT 1;

  IF fid IS NULL THEN
    SELECT v.firm_id INTO fid
      FROM public.firms p
      JOIN public.v2_firms v ON v.slug = p.slug
     WHERE p.registry_id = reg AND p.deleted_at IS NULL AND NOT coalesce(v.archived, false)
     ORDER BY v.firm_id
     LIMIT 1;
  END IF;

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

  SELECT p.slug INTO slg FROM public.firms p
   WHERE p.registry_id = reg AND p.deleted_at IS NULL AND nullif(btrim(p.slug), '') IS NOT NULL
   LIMIT 1;
  IF slg IS NULL THEN
    slg := coalesce(public._slugify(nm), public._slugify(reg));
  END IF;
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
  execute 'revoke all on function public.v2_research_add_firm(uuid, jsonb) from public, anon, authenticated';
  execute 'grant execute on function public.v2_research_add_firm(uuid, jsonb) to service_role';
end
$mig$;
