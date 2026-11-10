-- A new startup is identified by its website only.
-- Missing website, or a hosted-platform host, is rejected and does not count toward the per-firm rejection freeze.
-- A non-archived v2_startups row with that domain is a match: nothing is written to the row, the ref points at the existing startup_id, and it is not queued for the Checker.
-- No name check. A v2_startups_domain_uq race is treated as that same match.
-- An item that already carries startup_id (website fill) is unchanged.
-- v2_startups.domain is a generated column:
--   lower(split_part(regexp_replace(regexp_replace(website_url, '^https?://', '', 'i'), '^www\\.', '', 'i'), '/', 1))
-- The comparison uses that expression. The v2 schema is not created here. CI has no v2 function, so this is a no-op there.
-- Undo: supabase/rollbacks/20261110040000_v2_startup_website_identity.sql
-- Not applied to any database by this change.
do $mig$
begin
  if to_regprocedure('public.v2_research_submit(uuid,jsonb,boolean)') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;
  execute $v2fn$
CREATE OR REPLACE FUNCTION public.v2_research_submit(p_key_id uuid, p_items jsonb, p_dry_run boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'bots'
 SET statement_timeout TO '30s'
 SET lock_timeout TO '5s'
AS $function$
DECLARE
  ik bots.ingest_keys; bk public.v2_bot_keys; bot text; batch bigint;
  it jsonb; idx int := -1; firmkey text; firms text[] := '{}'; refused jsonb := '[]'; results jsonb := '[]';
  tbl text; box text; fact jsonb; p jsonb; k text; v jsonb; reason text; sid bigint; fid bigint; res jsonb;
  sec_id smallint; o_site text; empty_fill boolean; ft_id smallint;
  pkcol text; newid bigint; cols text; refs jsonb := '{}'; q_kind text; o jsonb; n jsonb; upd jsonb; diff boolean;
  rej_today int; firms_hour int; frz text; acc int := 0; rejn int := 0; held int := 0;
  src_tables text[] := ARRAY['v2_funds','v2_fund_assets','v2_startups','v2_startup_sectors','v2_deals','v2_people',
    'v2_person_firm_roles','v2_board_seats','v2_interviews','v2_legal_items','v2_sec_registration','v2_sec_fact_pills','v2_social_accounts',
    'v2_reviews','v2_firm_aum','v2_firm_contacts','v2_firm_registry_ids',
    'v2_investor_principles','v2_firm_stages','v2_firm_industries','v2_firm_types_firms','firm_fund_announcements','v2_firm_check_sizes','v2_firm_former_names'];
  firm_fields jsonb := '{"legal_name":"legal_name_source","founded_year":"founded_year_source","thesis_text":"thesis_source","hq_street":"hq_source","hq_suite":"hq_source","hq_city":"hq_source","hq_state":"hq_source","hq_postal":"hq_source","hq_country":"hq_source","website_url":null,"short_name":null}';
  blocked text[] := ARRAY['row_id','submission_id','archived','archive_reason','created_at','is_current','source_url_norm','archived_url_norm','link_dead','website_source'];
  src_keys text[] := ARRAY['source_url','source_level','source_date','source_date_precision','source_date_is_found_date','source_type','source_owner','archived_url','nothing_found'];
  v_st_web text; v_st_raw text; v_st_host text; v_st_id bigint; v_st_name text; v_st_note text; v_st_match boolean := false; v_cname text;
  v_site_reason text := 'website_url required: find this startup''s website or skip the startup and its deal';
  -- Hosted-platform domains are not a startup's own website. One list. The host or any subdomain of it is rejected.
  v_platform_hosts text[] := ARRAY['linktr.ee','medium.com','github.com','notion.site','wixsite.com','carrd.co','substack.com','linkedin.com','facebook.com','x.com','twitter.com','instagram.com'];
BEGIN
  SELECT * INTO ik FROM bots.ingest_keys WHERE id = p_key_id AND active;
  IF NOT FOUND OR ik.bot_id IS NULL THEN RETURN jsonb_build_object('ok',false,'error','this key is not linked to a bot'); END IF;
  bot := ik.bot_id;
  INSERT INTO public.v2_bot_keys (bot_name, key_hash) VALUES (bot, ik.key_hash)
    ON CONFLICT (bot_name) DO UPDATE SET key_hash = EXCLUDED.key_hash RETURNING * INTO bk;
  IF bk.frozen THEN
    RETURN jsonb_build_object('ok',false,'error',format('Key frozen: %s, %s', coalesce(bk.freeze_reason,'no reason'), to_char(bk.freeze_date AT TIME ZONE 'America/Los_Angeles','YYYY-MM-DD HH24:MI "PT"')));
  END IF;
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN RETURN jsonb_build_object('ok',false,'error','items must be a non-empty array'); END IF;
  IF jsonb_array_length(p_items) > 500 THEN RETURN jsonb_build_object('ok',false,'error','max 500 items per batch'); END IF;
  batch := nextval('public.v2_batch_seq');

  BEGIN  -- whole batch; rolled back at the end when p_dry_run
  FOR it IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    idx := idx + 1; reason := NULL; sid := NULL; newid := NULL; q_kind := NULL; res := NULL;
    v_st_match := false; v_st_id := NULL; v_st_name := NULL; v_st_raw := NULL; v_st_host := NULL; v_cname := NULL;
    IF jsonb_typeof(it) <> 'object' THEN
      results := results || jsonb_build_object('index',idx,'status','Rejected: item must be an object'); CONTINUE; END IF;
    firmkey := coalesce(it->>'firm_id', it->>'firm_ref');
    IF firmkey IS NULL THEN
      results := results || jsonb_build_object('index',idx,'status','Rejected: firm_id (existing firm) or firm_ref (new firm) required'); CONTINUE; END IF;
    IF NOT firmkey = ANY(firms) THEN
      IF cardinality(firms) >= 10 THEN
        refused := refused || jsonb_build_object('index',idx,'firm',firmkey,'status','Refused: batch over 10 firms; firms 11+ are refused, send them in the next batch (I1.5)'); CONTINUE; END IF;
      firms := firms || firmkey;
    END IF;
    tbl := it->>'table'; box := it->>'box'; fact := coalesce(it->'fact','{}');
    fid := CASE WHEN (it->>'firm_id') ~ '^\d+$' THEN (it->>'firm_id')::bigint END;
    IF it->>'firm_id' IS NOT NULL AND fid IS NULL THEN reason := 'firm_id must be a number';
    ELSIF box IS NULL OR box !~ '^[A-Z]{1,3}[0-9]{1,3}[a-z]?$' THEN reason := 'box required (e.g. F12)';
    ELSIF tbl IS NULL OR NOT (tbl = ANY(src_tables) OR tbl = 'v2_firms') THEN reason := format('unknown table "%s" (P9)', coalesce(tbl,''));
    ELSIF jsonb_typeof(fact) <> 'object' THEN reason := 'fact must be an object';
    ELSIF fid IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.v2_firms WHERE firm_id = fid) THEN reason := format('firm_id %s not found', fid);
    END IF;
    -- source checks (R2, P1, P2, S1-S4)
    IF reason IS NULL THEN
      fact := fact || jsonb_build_object('source_owner', coalesce(fact->>'source_owner', bot));
      IF coalesce(fact->>'source_url','') = '' THEN reason := 'no source link (source_url)';
      ELSIF (fact->>'source_url') ~* '(google\.[a-z.]+/search|bing\.com/search|duckduckgo\.com/\?|grok\.com|x\.com/i/grok|chatgpt\.com|perplexity\.ai/search)' THEN reason := 'source_url is a search/chat page; cite the page itself';
      ELSIF (fact->>'source_url') !~* '^(https?://)?(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)+(/[^\s]*)?$' THEN reason := 'source_url is not a valid link';
      ELSIF coalesce(fact->>'source_level','') !~ '^[1-4]$' THEN reason := 'no source level (source_level must be 1, 2, 3 or 4)';
      ELSIF coalesce(fact->>'source_date','') !~ '^\d{4}-\d{2}-\d{2}$' THEN reason := 'no source date (source_date YYYY-MM-DD)';
      ELSIF coalesce(fact->>'source_type','') = '' THEN reason := 'no source type (source_type)';
      END IF;
      IF reason IS NULL THEN
        BEGIN IF (fact->>'source_date')::date > current_date THEN reason := 'source_date is in the future'; END IF;
        EXCEPTION WHEN others THEN reason := 'source_date is not a real date'; END;
      END IF;
    END IF;
    IF reason IS NULL AND tbl = 'v2_sec_fact_pills' AND lower(btrim(coalesce(fact->>'fact_label',''))) IN ('staff','investment staff') THEN
      reason := 'Staff and Investment staff are not accepted';
    END IF;
    -- G5.2 (Alex 2026-11-04 12:40 PM PT): a review's reviewer_role / reviewer_company needs a valid reviewer_role_source_url
    IF reason IS NULL AND tbl = 'v2_reviews' AND (coalesce(btrim(fact->>'reviewer_role'),'') <> '' OR coalesce(btrim(fact->>'reviewer_company'),'') <> '') THEN
      IF coalesce(btrim(fact->>'reviewer_role_source_url'),'') = '' THEN reason := 'reviewer_role/reviewer_company sent without reviewer_role_source_url (G5.2)';
      ELSIF (fact->>'reviewer_role_source_url') ~* '(google\.[a-z.]+/search|bing\.com/search|duckduckgo\.com/\?|grok\.com|x\.com/i/grok|chatgpt\.com|perplexity\.ai/search)' THEN reason := 'reviewer_role_source_url is a search/chat page; cite the page itself (G5.2)';
      ELSIF (fact->>'reviewer_role_source_url') !~* '^https?://(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)+(/[^\s]*)?$' THEN reason := 'reviewer_role_source_url is not a valid link (G5.2)';
      END IF;
    END IF;
    -- G5.2.1 (Alex 2026-11-04 12:54 PM PT): a review_author that replaces the name on an existing review of the same quote/source
    -- (e.g. a username -> a real name) needs reviewer_name_source_url; any reviewer_name_source_url given must be a valid link
    IF reason IS NULL AND tbl = 'v2_reviews' THEN
      IF coalesce(btrim(fact->>'reviewer_name_source_url'),'') <> '' THEN
        IF (fact->>'reviewer_name_source_url') ~* '(google\.[a-z.]+/search|bing\.com/search|duckduckgo\.com/\?|grok\.com|x\.com/i/grok|chatgpt\.com|perplexity\.ai/search)' THEN reason := 'reviewer_name_source_url is a search/chat page; cite the page itself (G5.2.1)';
        ELSIF (fact->>'reviewer_name_source_url') !~* '^https?://(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)+(/[^\s]*)?$' THEN reason := 'reviewer_name_source_url is not a valid link (G5.2.1)';
        END IF;
      ELSIF coalesce(btrim(fact->>'review_author'),'') <> '' AND EXISTS (
        SELECT 1 FROM public.v2_reviews r WHERE r.firm_id = fid AND NOT r.archived
          AND coalesce(btrim(r.review_author),'') <> '' AND lower(btrim(r.review_author)) <> lower(btrim(fact->>'review_author'))
          AND (lower(rtrim(btrim(r.source_url),'/')) = lower(rtrim(btrim(fact->>'source_url'),'/')) OR btrim(r.quote) = btrim(fact->>'quote'))) THEN
        reason := 'review_author replaces the name on an existing review; send reviewer_name_source_url (the page that states the name) (G5.2.1)';
      END IF;
    END IF;
    -- 015: sector rows may name the ST5 word ("sector") instead of sector_id; max 2 per startup
    IF reason IS NULL AND tbl = 'v2_startup_sectors' AND fact ? 'sector' THEN
      SELECT sector_id INTO sec_id FROM public.v2_sector WHERE lower(name) = lower(trim(fact->>'sector'));
      IF sec_id IS NULL THEN reason := format('unknown sector "%s" (use one of the 18 ST5 sectors)', fact->>'sector');
      ELSIF fact ? 'sector_id' AND (fact->>'sector_id') IS DISTINCT FROM sec_id::text THEN reason := 'sector and sector_id disagree';
      ELSE fact := (fact - 'sector') || jsonb_build_object('sector_id', sec_id); END IF;
    END IF
;
    IF reason IS NULL AND tbl = 'v2_firm_types_firms' AND fact ? 'firm_type' THEN
      SELECT t.firm_type_id INTO ft_id FROM public.v2_firm_type t WHERE lower(t.name) = lower(btrim(fact->>'firm_type')) ORDER BY t.firm_type_id LIMIT 1;
      IF ft_id IS NULL THEN reason := format('unknown firm type "%s"', fact->>'firm_type');
      ELSIF fact ? 'firm_type_id' AND (fact->>'firm_type_id') IS DISTINCT FROM ft_id::text THEN reason := 'firm_type and firm_type_id disagree';
      ELSE fact := (fact - 'firm_type') || jsonb_build_object('firm_type_id', ft_id); END IF;
    END IF;
    IF reason IS NULL AND tbl = 'v2_investor_principles' THEN
      IF char_length(btrim(coalesce(fact->>'quote',''))) = 0 THEN reason := 'quote required (exact excerpt, 150 characters or less)';
      ELSIF char_length(btrim(fact->>'quote')) > 150 THEN reason := 'quote is over 150 characters (exact excerpt, 150 characters or less)';
      ELSIF NOT (fact ? 'display_order') AND fid IS NOT NULL THEN
        fact := fact || jsonb_build_object('display_order', coalesce((SELECT max(pr.display_order) FROM public.v2_investor_principles pr WHERE pr.firm_id = fid), 0) + 1);
      END IF;
      IF reason IS NULL AND nullif(btrim(fact->>'published_at'),'') IS NULL THEN
        fact := fact - 'published_at';
      END IF;
    END IF;
    IF reason IS NULL AND tbl = 'v2_firm_stages' AND NOT (fact ? 'read_on') AND coalesce(fact->>'source_date','') <> '' THEN
      fact := fact || jsonb_build_object('read_on', fact->>'source_date');
    END IF;
    IF reason IS NULL AND tbl = 'v2_firm_industries' AND NOT (fact ? 'date_read') AND coalesce(fact->>'source_date','') <> '' THEN
      fact := fact || jsonb_build_object('date_read', fact->>'source_date');
    END IF;
    IF reason IS NULL AND tbl = 'v2_firm_check_sizes' THEN
      IF fact ? 'currency' AND upper(btrim(coalesce(fact->>'currency',''))) <> 'USD' THEN
        reason := 'check size currency must be USD';
      ELSIF fact ? 'currency' THEN
        fact := fact - 'currency';
      END IF;
      IF reason IS NULL AND NOT (fact ? 'read_on') AND coalesce(fact->>'source_date','') <> '' THEN
        fact := fact || jsonb_build_object('read_on', fact->>'source_date');
      END IF;
      IF reason IS NULL AND nullif(btrim(coalesce(fact->>'amount_text','')),'') IS NULL THEN
        reason := 'check size amount_text is required (source excerpt, not shown)';
      END IF;
      IF reason IS NULL AND fact ? 'min_usd' AND fact->'min_usd' <> 'null'::jsonb AND btrim(coalesce(fact->>'min_usd','')) !~ '^[1-9][0-9]*$' THEN
        reason := 'check size min_usd must be a positive whole number of US dollars';
      END IF;
      IF reason IS NULL AND fact ? 'max_usd' AND fact->'max_usd' <> 'null'::jsonb AND btrim(coalesce(fact->>'max_usd','')) !~ '^[1-9][0-9]*$' THEN
        reason := 'check size max_usd must be a positive whole number of US dollars';
      END IF;
      IF reason IS NULL AND nullif(btrim(coalesce(fact->>'min_usd','')),'') IS NULL AND nullif(btrim(coalesce(fact->>'max_usd','')),'') IS NULL THEN
        reason := 'check size needs min_usd or max_usd';
      END IF;
      IF reason IS NULL AND nullif(btrim(coalesce(fact->>'min_usd','')),'') IS NOT NULL AND nullif(btrim(coalesce(fact->>'max_usd','')),'') IS NOT NULL AND (btrim(fact->>'min_usd'))::numeric > (btrim(fact->>'max_usd'))::numeric THEN
        reason := 'check size min_usd is greater than max_usd';
      END IF;
    END IF;
    IF reason IS NULL AND tbl = 'firm_fund_announcements' THEN
      IF NOT (fact ? 'url') AND coalesce(fact->>'source_url','') <> '' THEN fact := fact || jsonb_build_object('url', fact->>'source_url'); END IF;
      IF NOT (fact ? 'retrieved_on') AND coalesce(fact->>'source_date','') <> '' THEN fact := fact || jsonb_build_object('retrieved_on', fact->>'source_date'); END IF;
    END IF;
    IF reason IS NULL THEN
      SELECT string_agg(key, ', ') INTO k FROM jsonb_object_keys(fact) key WHERE key = ANY(blocked) OR key LIKE '%\_norm';
      IF k IS NOT NULL THEN reason := 'field not allowed (set by the database): '||k; END IF;
    END IF;
    IF reason IS NULL AND tbl <> 'v2_firms' THEN
      SELECT string_agg(key, ', ') INTO k FROM jsonb_object_keys(fact) key
        WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns c WHERE c.table_schema='public' AND c.table_name=tbl AND c.column_name=key);
      IF k IS NOT NULL THEN reason := 'unknown field: '||k; END IF;
    END IF;
    -- resolve @refs from earlier items of this batch
    p := '{}';
    IF reason IS NULL THEN
      FOR k, v IN SELECT * FROM jsonb_each(fact) LOOP
        IF jsonb_typeof(v) = 'string' AND left(v#>>'{}',1) = '@' THEN
          IF refs ? substr(v#>>'{}',2) THEN p := p || jsonb_build_object(k, refs->substr(v#>>'{}',2));
          ELSE reason := format('ref %s not found in this batch (the item that makes it was rejected, held, or comes later)', v#>>'{}'); EXIT; END IF;
        ELSE p := p || jsonb_build_object(k, v); END IF;
      END LOOP;
      IF tbl <> 'v2_firms' AND p ? 'firm_id' = false AND EXISTS (SELECT 1 FROM information_schema.columns c WHERE c.table_schema='public' AND c.table_name=tbl AND c.column_name='firm_id') THEN
        p := p || jsonb_build_object('firm_id', fid); END IF;
    END IF;

    INSERT INTO public.v2_research_submissions (batch_id, firm_id, bot_key_id, target_box, payload)
      VALUES (batch, fid, bk.bot_key_id, coalesce(box,'?'), jsonb_build_object('target_table',tbl,'fact',coalesce(it->'fact','{}'::jsonb),'firm_ref',it->>'firm_ref','ref',it->>'ref','origin',it->>'note','source_owner',coalesce(fact->>'source_owner',bot),'item_index',idx))
      RETURNING submission_id INTO sid;

    IF reason IS NULL AND tbl = 'v2_firms' THEN
      IF fid IS NULL THEN  -- only the publish step creates a firm (F1.3.1)
        reason := NULL; q_kind := 'new-firm';
        INSERT INTO public.v2_checker_queue (submission_id, firm_id, kind, table_name, new_value) VALUES (sid, NULL, 'new-firm', tbl, p);
        UPDATE public.v2_research_submissions SET status = 'Held: new firm waits for the Checker (F1.3.1)' WHERE submission_id = sid;
        INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, submission_id, new_value, result) VALUES (bot, NULL, box, tbl, sid, p, 'Blocked: held, new firm waits for the Checker');
        held := held + 1;
        results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Held: new firm waits for the Checker (F1.3.1)','checker_queued','new-firm');
        CONTINUE;
      END IF;
      SELECT string_agg(key, ', ') INTO k FROM jsonb_object_keys(p) key WHERE NOT (key = ANY(src_keys) OR firm_fields ? key);
      IF k IS NOT NULL THEN reason := 'unknown firm field: '||k||' (allowed: '||(SELECT string_agg(x,', ') FROM jsonb_object_keys(firm_fields) x)||')'; END IF;
      IF reason IS NULL AND NOT EXISTS (SELECT 1 FROM jsonb_object_keys(p) key WHERE firm_fields ? key) THEN reason := 'no firm field to set'; END IF;
      IF reason IS NULL THEN
        SELECT to_jsonb(f) INTO o FROM public.v2_firms f WHERE firm_id = fid;
        upd := '{}'; diff := false; empty_fill := false;
        FOR k, v IN SELECT * FROM jsonb_each(p) WHERE firm_fields ? key LOOP
          upd := upd || jsonb_build_object(k, v);
          IF firm_fields->>k IS NOT NULL THEN upd := upd || jsonb_build_object(firm_fields->>k, jsonb_build_object('url',p->>'source_url','level',(p->>'source_level')::int,'date',p->>'source_date')); END IF;
          IF o->k IS NOT NULL AND o->k <> 'null'::jsonb AND nullif(btrim(o->>k),'') IS NOT NULL AND (o->>k) IS DISTINCT FROM (v#>>'{}') THEN diff := true;
          ELSIF nullif(btrim(v#>>'{}'),'') IS NOT NULL AND (o->k IS NULL OR o->k = 'null'::jsonb OR nullif(btrim(o->>k),'') IS NULL) THEN empty_fill := true; END IF;
        END LOOP;
        IF diff THEN  -- changed key fact: never overwrite directly (P15)
          INSERT INTO public.v2_checker_queue (submission_id, firm_id, kind, table_name, row_id, old_value, new_value)
            VALUES (sid, fid, 'changed-key-fact', tbl, fid, (SELECT jsonb_object_agg(x, o->x) FROM jsonb_object_keys(upd) x), upd);
          UPDATE public.v2_research_submissions SET status = 'Held: changed key fact waits for the Checker (P15)' WHERE submission_id = sid;
          INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result) VALUES (bot, fid, box, tbl, fid, sid, o, upd, 'Blocked: held, changed key fact waits for the Checker');
          held := held + 1;
          results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Held: changed key fact waits for the Checker (P15)','checker_queued','changed-key-fact');
          CONTINUE;
        END IF;
        IF empty_fill THEN
          INSERT INTO public.v2_checker_queue (submission_id, firm_id, kind, table_name, row_id, old_value, new_value)
            VALUES (sid, fid, 'changed-key-fact', tbl, fid, (SELECT jsonb_object_agg(x, o->x) FROM jsonb_object_keys(upd) x), upd);
          UPDATE public.v2_research_submissions SET status = 'Held: empty firm field waits for the Checker' WHERE submission_id = sid;
          INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
            VALUES (bot, fid, box, tbl, fid, sid, (SELECT jsonb_object_agg(x, o->x) FROM jsonb_object_keys(upd) x), upd, 'Blocked: held, empty firm field waits for the Checker');
          held := held + 1;
          results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Held: empty firm field waits for the Checker','checker_queued','changed-key-fact');
          CONTINUE;
        END IF;
        BEGIN
          EXECUTE format('UPDATE public.v2_firms t SET (%s) = (SELECT %s FROM jsonb_populate_record(NULL::public.v2_firms, $1)), last_checked_date = current_date WHERE firm_id = $2 RETURNING to_jsonb(t)',
            (SELECT string_agg(format('%I',x),',') FROM jsonb_object_keys(upd) x), (SELECT string_agg(format('%I',x),',') FROM jsonb_object_keys(upd) x)) INTO n USING upd, fid;
          UPDATE public.v2_research_submissions SET status = 'Accepted' WHERE submission_id = sid;
          INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
            VALUES (bot, fid, box, tbl, fid, sid, (SELECT jsonb_object_agg(x, o->x) FROM jsonb_object_keys(upd) x), (SELECT jsonb_object_agg(x, n->x) FROM jsonb_object_keys(upd) x), 'Accepted');
          acc := acc + 1;
          results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Accepted','table',tbl,'row_id',fid);
          CONTINUE;
        EXCEPTION WHEN others THEN reason := left(SQLERRM, 300); END;
      END IF;
    END IF;

    -- 015: sector row for a startup: max 2 per startup (11. startup_sectors), startup must exist
    IF reason IS NULL AND tbl = 'v2_startup_sectors' THEN
      IF (p->>'startup_id') !~ '^\d+$' OR NOT EXISTS (SELECT 1 FROM public.v2_startups WHERE startup_id = (p->>'startup_id')::bigint AND NOT archived) THEN
        reason := format('startup_id %s not found', coalesce(p->>'startup_id',''));
      ELSIF EXISTS (SELECT 1 FROM public.v2_startup_sectors WHERE startup_id = (p->>'startup_id')::bigint AND sector_id = (p->>'sector_id')::smallint) THEN
        reason := 'sector already set for this startup';
      ELSIF (SELECT count(*) FROM public.v2_startup_sectors WHERE startup_id = (p->>'startup_id')::bigint AND NOT archived) >= 2 THEN
        reason := 'startup already has 2 sectors (max 2)';
      END IF;
    END IF;
    -- 015: website fill for an EXISTING startup (fact has startup_id): fills an empty website_url only; never a new startup, never overwrites
    IF reason IS NULL AND tbl = 'v2_startups' AND p ? 'startup_id' THEN
      SELECT string_agg(key, ', ') INTO k FROM jsonb_object_keys(p) key WHERE NOT (key = ANY(src_keys) OR key IN ('startup_id','website_url'));
      IF k IS NOT NULL THEN reason := 'existing startup: only website_url can be filled (not allowed: '||k||')';
      ELSIF coalesce(p->>'website_url','') = '' THEN reason := 'existing startup: website_url required';
      ELSIF (p->>'startup_id') !~ '^\d+$' THEN reason := 'startup_id must be a number';
      ELSE
        SELECT to_jsonb(s) INTO o FROM public.v2_startups s WHERE startup_id = (p->>'startup_id')::bigint AND NOT archived;
        IF o IS NULL THEN reason := format('startup_id %s not found', p->>'startup_id');
        ELSE
          o_site := nullif(o->>'website_url','');
          IF o_site IS NOT NULL THEN
            IF lower(regexp_replace(regexp_replace(o_site,'^(https?://)?(www\.)?',''),'/+$','')) = lower(regexp_replace(regexp_replace(p->>'website_url','^(https?://)?(www\.)?',''),'/+$','')) THEN
              UPDATE public.v2_research_submissions SET status = 'Accepted' WHERE submission_id = sid;
              INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
                VALUES (bot, fid, box, tbl, (o->>'startup_id')::bigint, sid, jsonb_build_object('website_url',o_site), jsonb_build_object('website_url',p->>'website_url'), 'Accepted');
              acc := acc + 1;
              results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Accepted','table',tbl,'row_id',(o->>'startup_id')::bigint,'note','website already set to the same site; nothing changed');
              CONTINUE;
            END IF;
            reason := 'startup already has a different website_url; never overwritten (P15)';
          ELSIF (p->>'source_level') = '4' THEN reason := 'website fill needs source_level 1-3';
          ELSE
            INSERT INTO public.v2_checker_queue (submission_id, firm_id, kind, table_name, row_id, old_value, new_value)
              VALUES (sid, fid, 'changed-key-fact', tbl, (o->>'startup_id')::bigint,
                jsonb_build_object('website_url', NULL),
                jsonb_build_object('website_url', p->>'website_url',
                  'website_source', jsonb_build_object('url',p->>'source_url','level',(p->>'source_level')::int,'date',p->>'source_date','type',p->>'source_type','owner',p->>'source_owner','submission_id',sid)));
            UPDATE public.v2_research_submissions SET status = 'Held: empty startup website waits for the Checker' WHERE submission_id = sid;
            INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
              VALUES (bot, fid, box, tbl, (o->>'startup_id')::bigint, sid, jsonb_build_object('website_url',NULL), jsonb_build_object('website_url',p->>'website_url'), 'Blocked: held, empty startup website waits for the Checker');
            held := held + 1;
            IF it->>'ref' IS NOT NULL THEN refs := refs || jsonb_build_object(it->>'ref', (o->>'startup_id')::bigint); END IF;
            results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Held: empty startup website waits for the Checker','table',tbl,'row_id',(o->>'startup_id')::bigint,'checker_queued','changed-key-fact');
            CONTINUE;
          END IF;
        END IF;
      END IF;
    END IF;

    -- New startup (no startup_id): the website is the only identity. A matching name does not matter.
    -- v2_startups.domain is generated as lower(split_part(regexp_replace(regexp_replace(website_url, '^https?://', '', 'i'), '^www\.', '', 'i'), '/', 1)).
    -- The lookup uses that expression. A port, query, fragment, or trailing dot left on that host is stripped for the comparison only.
    IF reason IS NULL AND tbl = 'v2_startups' AND NOT (p ? 'startup_id') THEN
      v_st_web := btrim(coalesce(p->>'website_url', ''));
      IF v_st_web IS DISTINCT FROM coalesce(p->>'website_url', '') THEN
        p := p || jsonb_build_object('website_url', v_st_web);
      END IF;
      v_st_raw := lower(split_part(regexp_replace(regexp_replace(v_st_web, '^https?://', '', 'i'), '^www\.', '', 'i'), '/', 1));
      v_st_host := regexp_replace(regexp_replace(split_part(split_part(v_st_raw, '?', 1), '#', 1), ':[0-9]+$', ''), '\.+$', '');
      IF v_st_host = '' OR EXISTS (
        SELECT 1 FROM unnest(v_platform_hosts) AS h(host)
        WHERE v_st_host = h.host OR right(v_st_host, length(h.host) + 1) = '.' || h.host
      ) THEN
        reason := v_site_reason;
      ELSE
        SELECT s.startup_id, s.startup_name INTO v_st_id, v_st_name
        FROM public.v2_startups s
        WHERE NOT s.archived AND s.domain IS NOT NULL AND s.domain <> '' AND s.domain = v_st_raw
        ORDER BY s.startup_id
        LIMIT 1;
        IF v_st_id IS NULL THEN
          SELECT s.startup_id, s.startup_name INTO v_st_id, v_st_name
          FROM public.v2_startups s
          WHERE NOT s.archived AND s.domain IS NOT NULL AND s.domain <> ''
            AND regexp_replace(regexp_replace(split_part(split_part(s.domain, '?', 1), '#', 1), ':[0-9]+$', ''), '\.+$', '') = v_st_host
          ORDER BY s.startup_id
          LIMIT 1;
        END IF;
        IF v_st_id IS NOT NULL THEN v_st_match := true; END IF;
      END IF;
    END IF;

    IF reason IS NULL AND tbl = 'v2_deals' AND btrim(coalesce(p->>'deal_date','')) ~ '^\d{4}$' THEN
      -- bare year stored as January 1 with the existing precision. The page shows the year only.
      p := p || jsonb_build_object('deal_date', btrim(p->>'deal_date') || '-01-01', 'deal_date_precision', 'year');
    END IF;
    IF reason IS NULL AND NOT v_st_match THEN
      IF (p->>'source_level') = '4' THEN p := p || '{"archived":true,"archive_reason":"L4 kept archived (R2)"}'; END IF;
      p := p || jsonb_build_object('submission_id', sid);
      SELECT string_agg(format('%I', key), ',') INTO cols FROM jsonb_object_keys(p) key;
      BEGIN
        EXECUTE format('INSERT INTO public.%I AS t (%s) SELECT %s FROM jsonb_populate_record(NULL::public.%I, $1) RETURNING to_jsonb(t)', tbl, cols, cols, tbl) INTO res USING p;
      EXCEPTION
        WHEN unique_violation THEN
          GET STACKED DIAGNOSTICS v_cname = CONSTRAINT_NAME;
          IF tbl = 'v2_startups' AND NOT (p ? 'startup_id') AND (v_cname = 'v2_startups_domain_uq' OR position('v2_startups_domain_uq' in SQLERRM) > 0) THEN
            SELECT s.startup_id, s.startup_name INTO v_st_id, v_st_name
            FROM public.v2_startups s
            WHERE NOT s.archived AND s.domain IS NOT NULL AND s.domain <> '' AND s.domain = v_st_raw
            ORDER BY s.startup_id
            LIMIT 1;
            IF v_st_id IS NULL THEN
              reason := left(SQLERRM, 300);
            ELSE
              v_st_match := true;
            END IF;
          ELSE
            reason := left(SQLERRM, 300);
          END IF;
        WHEN others THEN reason := left(SQLERRM, 300);
      END;
    END IF;

    IF v_st_match THEN
      v_st_note := format('matched existing startup %s by website (submitted "%s", existing "%s")', v_st_id, coalesce(nullif(btrim(p->>'startup_name'), ''), '(none)'), coalesce(nullif(btrim(v_st_name), ''), '(none)'));
      UPDATE public.v2_research_submissions SET status = 'Accepted' WHERE submission_id = sid;
      INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
        VALUES (bot, fid, box, tbl, v_st_id, sid,
          jsonb_build_object('startup_id', v_st_id, 'startup_name', v_st_name),
          jsonb_build_object('startup_name', p->>'startup_name', 'website_url', p->>'website_url'),
          'Accepted');
      IF it->>'ref' IS NOT NULL THEN refs := refs || jsonb_build_object(it->>'ref', v_st_id); END IF;
      acc := acc + 1;
      results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Accepted','table',tbl,'row_id',v_st_id,'matched_startup_id',v_st_id,'note',v_st_note);
      CONTINUE;
    END IF;

    IF reason IS NOT NULL THEN
      UPDATE public.v2_research_submissions SET status = 'Rejected: '||reason WHERE submission_id = sid;
      INSERT INTO public.v2_rejected_rows (payload, target_table, error_message, source_owner, submission_id, status)
        VALUES (coalesce(it->'fact','{}'::jsonb) || jsonb_build_object('_item', it - 'fact'), coalesce(tbl,'?'), reason, left(coalesce(fact->>'source_owner',bot),200), sid, 'new');
      INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, submission_id, new_value, result)
        VALUES (bot, fid, coalesce(box,'?'), coalesce(tbl,'?'), sid, it, 'Rejected: '||reason);
      rejn := rejn + 1;
      results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Rejected: '||reason);
      CONTINUE;
    END IF;

    pkcol := CASE tbl WHEN 'v2_funds' THEN 'fund_id' WHEN 'v2_startups' THEN 'startup_id' WHEN 'v2_people' THEN 'person_id'
                      WHEN 'v2_deals' THEN 'deal_id' WHEN 'v2_legal_items' THEN 'legal_item_id' WHEN 'v2_investor_principles' THEN 'id' WHEN 'v2_firm_stages' THEN 'id' WHEN 'v2_firm_industries' THEN 'id' WHEN 'firm_fund_announcements' THEN 'id' WHEN 'v2_firm_check_sizes' THEN 'id' ELSE 'row_id' END;
    newid := (res->>pkcol)::bigint;
    -- 011: new rows stay hidden until the Checker passes them (v2_publish_queue_item sets is_current/shown)
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name=tbl AND column_name='is_current') THEN
      EXECUTE format('UPDATE public.%I SET is_current = false WHERE submission_id = $1', tbl) USING sid;
    END IF;
    IF tbl = 'v2_deals' THEN UPDATE public.v2_deals SET shown = false WHERE submission_id = sid; END IF;
    IF it->>'ref' IS NOT NULL THEN refs := refs || jsonb_build_object(it->>'ref', newid); END IF;
    UPDATE public.v2_research_submissions SET status = 'Accepted' WHERE submission_id = sid;
    INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
      VALUES (bot, fid, box, tbl, newid, sid, NULL, res, 'Accepted');
    -- name-only rows go to the Checker (glossary 30, C4.2)
    IF NOT EXISTS (SELECT 1 FROM jsonb_object_keys(p) key WHERE NOT (key = ANY(src_keys) OR key IN ('firm_id','submission_id','archived','archive_reason') OR key LIKE '%\_name')) THEN
      q_kind := 'name-only';
      INSERT INTO public.v2_checker_queue (submission_id, firm_id, kind, table_name, row_id, new_value) VALUES (sid, fid, 'name-only', tbl, newid, res);
    ELSE  -- 011: every accepted item goes live only after the Checker passes it (Checker-first, R4.1; covers 010 LP rows too)
      q_kind := 'accepted-item';
      INSERT INTO public.v2_checker_queue (submission_id, firm_id, kind, table_name, row_id, new_value) VALUES (sid, fid, 'accepted-item', tbl, newid, res);
    END IF;
    acc := acc + 1;
    results := results || jsonb_strip_nulls(jsonb_build_object('index',idx,'submission_id',sid,'status','Accepted','table',tbl,'row_id',newid,'checker_queued',q_kind,
      'note',CASE WHEN (p->>'source_level')='4' THEN 'L4: kept archived (R2)' END));
  END LOOP;

  -- freeze rules (I2.7)
  SELECT coalesce(max(firm_rej), 0)::int INTO rej_today FROM (
    SELECT count(*) AS firm_rej FROM public.v2_research_submissions
    WHERE bot_key_id = bk.bot_key_id AND status LIKE 'Rejected:%'
      AND status IS DISTINCT FROM ('Rejected: ' || v_site_reason)
      AND received_at >= date_trunc('day', now() AT TIME ZONE 'America/Los_Angeles') AT TIME ZONE 'America/Los_Angeles'
    GROUP BY coalesce(firm_id::text, payload->>'firm_ref')
  ) one_firm;
  SELECT count(DISTINCT coalesce(firm_id::text, payload->>'firm_ref')) INTO firms_hour FROM public.v2_research_submissions
    WHERE bot_key_id = bk.bot_key_id AND received_at > now() - interval '1 hour';
  frz := CASE WHEN rej_today >= 100 THEN format('%s rejections today for one firm', rej_today) WHEN firms_hour > 100 THEN format('%s firms in the last hour', firms_hour) END;
  IF frz IS NOT NULL AND NOT p_dry_run THEN
    UPDATE public.v2_bot_keys SET frozen = true, freeze_date = now(), freeze_reason = frz,
      freeze_count_7d = CASE WHEN freeze_date > now() - interval '7 days' THEN coalesce(freeze_count_7d,0) + 1 ELSE 1 END
      WHERE bot_key_id = bk.bot_key_id;
    INSERT INTO public.v2_change_log (actor, box, table_name, row_id, new_value, result)
      VALUES ('v2_research_submit', 'I2', 'v2_bot_keys', bk.bot_key_id, jsonb_build_object('bot',bot,'frozen',true,'reason',frz), 'Blocked: Key frozen: '||frz);
  END IF;

  IF p_dry_run THEN RAISE EXCEPTION 'v2_dry_run_rollback'; END IF;
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'v2_dry_run_rollback' THEN RAISE; END IF;
  END;

  RETURN jsonb_strip_nulls(jsonb_build_object('ok', true, 'bot_id', bot, 'dry_run', p_dry_run, 'batch_id', CASE WHEN NOT p_dry_run THEN batch END,
    'accepted', acc, 'rejected', rejn, 'held', held, 'refused', jsonb_array_length(refused), 'firms', cardinality(firms),
    'results', results, 'refused_items', CASE WHEN jsonb_array_length(refused) > 0 THEN refused END,
    'key_frozen', CASE WHEN frz IS NOT NULL AND NOT p_dry_run THEN format('Key frozen: %s, %s', frz, to_char(now() AT TIME ZONE 'America/Los_Angeles','YYYY-MM-DD HH24:MI "PT"')) END,
    'would_freeze', CASE WHEN frz IS NOT NULL AND p_dry_run THEN frz END));
END $function$

$v2fn$;
end
$mig$;
