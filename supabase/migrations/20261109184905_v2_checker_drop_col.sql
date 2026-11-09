-- 20261109184905_v2_checker_drop_col: rename the drop_fields loop variable.
-- It was f, which is also the v2_firms alias in the firm-field confirm path,
-- so confirm failed with SQLSTATE 42702. The variable is now v_drop_col.
-- No other logic change.
-- Undo: run supabase/migrations/20261109060000_v2_checker_drop_fields.sql again.
do $mig$
begin
  if to_regprocedure('public.v2_checker_action(uuid,text,jsonb,boolean)') is null then
    raise notice 'v2_checker_action not present; skipped';
    return;
  end if;
  execute $fn$
CREATE OR REPLACE FUNCTION public.v2_checker_action(p_key_id uuid, p_action text, p_args jsonb DEFAULT '{}'::jsonb, p_dry_run boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'bots'
 SET statement_timeout TO '30s'
 SET lock_timeout TO '5s'
AS $function$
DECLARE
  ik bots.ingest_keys; q public.v2_checker_queue; bot text; qid bigint; verdict text; reason text; sources jsonb;
  o jsonb; n jsonb; k text; v jsonb; conflicts text[] := '{}'; outcome text; pkcol text; res jsonb; lim int;
  firm_fields text[] := ARRAY['legal_name','founded_year','thesis_text','hq_street','hq_suite','hq_city','hq_state','hq_postal','hq_country','website_url','short_name'];
  drops jsonb; dropf text[]; drop_ok text[]; bad text; v_drop_col text; dropped jsonb; r jsonb;
BEGIN
  SELECT * INTO ik FROM bots.ingest_keys WHERE id = p_key_id AND active;
  IF NOT FOUND OR ik.bot_id IS DISTINCT FROM 'toxy-checker' THEN
    RETURN jsonb_build_object('ok',false,'error','only the Checker key may use this action'); END IF;
  bot := ik.bot_id;

  IF p_action = 'list_queue' THEN
    lim := LEAST(GREATEST(coalesce(CASE WHEN (p_args->>'limit') ~ '^\d+$' THEN (p_args->>'limit')::int END, 100), 1), 500);
    RETURN jsonb_build_object('ok',true,'bot_id',bot,'dry_run',p_dry_run,
      'pending',(SELECT count(*) FROM v2_checker_queue WHERE status='open' AND NOT archived),
      'items',coalesce((SELECT jsonb_agg(x ORDER BY (x->>'queue_id')::bigint) FROM (
        SELECT jsonb_build_object('queue_id',c.queue_id,'submission_id',c.submission_id,'firm_id',c.firm_id,'kind',c.kind,'table',c.table_name,
          'row_id',c.row_id,'old_value',c.old_value,'new_value',c.new_value,'created_at',c.created_at,
          'sent_by',(SELECT bk.bot_name FROM v2_research_submissions s JOIN v2_bot_keys bk ON bk.bot_key_id=s.bot_key_id WHERE s.submission_id=c.submission_id),
          'box',(SELECT s.target_box FROM v2_research_submissions s WHERE s.submission_id=c.submission_id)) x
        FROM v2_checker_queue c WHERE c.status='open' AND NOT c.archived ORDER BY c.queue_id LIMIT lim) t),'[]'));
  END IF;

  IF p_action <> 'verdict' THEN RETURN jsonb_build_object('ok',false,'error','action must be submit, list_queue or verdict'); END IF;
  qid := CASE WHEN (p_args->>'id') ~ '^\d+$' THEN (p_args->>'id')::bigint END;
  verdict := p_args->>'verdict'; reason := nullif(trim(coalesce(p_args->>'reason','')),''); sources := coalesce(p_args->'sources','[]');
  IF qid IS NULL THEN RETURN jsonb_build_object('ok',false,'error','id (queue_id number) required'); END IF;
  IF verdict IS NULL OR verdict NOT IN ('confirm','reject') THEN RETURN jsonb_build_object('ok',false,'error','verdict must be confirm or reject'); END IF;
  IF reason IS NULL THEN RETURN jsonb_build_object('ok',false,'error','reason required'); END IF;
  IF jsonb_typeof(sources) <> 'array' THEN RETURN jsonb_build_object('ok',false,'error','sources must be an array of links'); END IF;
  IF verdict = 'confirm' AND jsonb_array_length(sources) = 0 THEN RETURN jsonb_build_object('ok',false,'error','confirm needs at least one source link'); END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(sources) e WHERE coalesce(CASE WHEN jsonb_typeof(e)='object' THEN e->>'url' ELSE e#>>'{}' END,'') !~* '^(https?://)?(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)+(/[^\s]*)?$'
     OR coalesce(CASE WHEN jsonb_typeof(e)='object' THEN e->>'url' ELSE e#>>'{}' END,'') ~* '(google\.[a-z.]+/search|bing\.com/search|duckduckgo\.com/\?|grok\.com|x\.com/i/grok|chatgpt\.com|perplexity\.ai/search)') THEN
    RETURN jsonb_build_object('ok',false,'error','each source must be a real page link (not a search/chat page)'); END IF;

  SELECT * INTO q FROM v2_checker_queue WHERE queue_id = qid FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error',format('queue item %s not found', qid)); END IF;
  IF q.archived OR q.status <> 'open' THEN RETURN jsonb_build_object('ok',false,'error',format('queue item %s is not pending (status %s)', qid, q.status)); END IF;

  -- drop_fields (optional, confirm only): blank these optional details on the row and publish the rest.
  -- Strict allowlist; never the name, source fields, ids or foreign keys. Absent = old behavior.
  drops := p_args->'drop_fields';
  IF drops IS NOT NULL AND jsonb_typeof(drops) <> 'null' THEN
    IF verdict <> 'confirm' THEN RETURN jsonb_build_object('ok',false,'error','drop_fields only works with verdict confirm'); END IF;
    IF jsonb_typeof(drops) <> 'array' OR jsonb_array_length(drops) = 0
       OR EXISTS (SELECT 1 FROM jsonb_array_elements(drops) e WHERE jsonb_typeof(e) <> 'string') THEN
      RETURN jsonb_build_object('ok',false,'error','drop_fields must be a non-empty list of field names'); END IF;
    SELECT array_agg(DISTINCT e ORDER BY e) INTO dropf FROM jsonb_array_elements_text(drops) e;
    drop_ok := CASE WHEN q.kind IN ('name-only','accepted-item') AND q.table_name = 'v2_people'
                    THEN ARRAY['x_url','x_followers','linkedin_url','linkedin_followers','photo_url'] ELSE '{}'::text[] END;
    SELECT string_agg(x, ', ') INTO bad FROM unnest(dropf) x WHERE NOT (x = ANY(drop_ok));
    IF bad IS NOT NULL THEN
      RETURN jsonb_build_object('ok',false,'error',format('drop_fields: cannot drop %s from %s (allowed: %s)', bad, q.table_name,
        coalesce(nullif(array_to_string(drop_ok, ', '), ''), 'none'))); END IF;
  END IF;

  BEGIN  -- rolled back at the end when p_dry_run
    pkcol := CASE q.table_name WHEN 'v2_funds' THEN 'fund_id' WHEN 'v2_startups' THEN 'startup_id' WHEN 'v2_people' THEN 'person_id'
                  WHEN 'v2_deals' THEN 'deal_id' WHEN 'v2_legal_items' THEN 'legal_item_id' WHEN 'v2_firms' THEN 'firm_id' WHEN 'v2_investor_principles' THEN 'id' WHEN 'v2_firm_stages' THEN 'id' WHEN 'v2_firm_industries' THEN 'id' WHEN 'firm_fund_announcements' THEN 'id' WHEN 'v2_firm_check_sizes' THEN 'id' ELSE 'row_id' END;
    IF verdict = 'reject' THEN
      IF q.kind IN ('name-only','accepted-item') AND q.row_id IS NOT NULL AND q.table_name <> 'v2_firms' THEN  -- row was published at submit; archive it (never delete)
        EXECUTE format('UPDATE public.%I SET archived = true, archive_reason = $1 WHERE %I = $2', q.table_name, pkcol)
          USING left('Checker rejected: '||reason, 300), q.row_id;
      END IF;
      UPDATE v2_checker_queue SET status = 'failed' WHERE queue_id = qid;
      UPDATE v2_research_submissions SET status = left('Rejected: Checker: '||reason, 500) WHERE submission_id = q.submission_id;
      outcome := CASE WHEN q.kind IN ('name-only','accepted-item') AND q.table_name <> 'v2_firms' THEN 'Rejected: row archived, not published' ELSE 'Rejected: not applied' END;
    ELSIF q.kind IN ('name-only','accepted-item') THEN  -- R4.1: a passed item is published right away
      IF dropf IS NOT NULL THEN  -- blank only the dropped details, keep the rest
        EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE %I = $1 AND submission_id = $2', q.table_name, pkcol) INTO r USING q.row_id, q.submission_id;
        dropped := (SELECT jsonb_object_agg(x, r->x) FROM unnest(dropf) x);
        FOREACH v_drop_col IN ARRAY dropf LOOP
          EXECUTE format('UPDATE public.%I SET %I = NULL WHERE %I = $1 AND submission_id = $2', q.table_name, v_drop_col, pkcol) USING q.row_id, q.submission_id;
        END LOOP;
      END IF;
      UPDATE v2_checker_queue SET status = 'passed' WHERE queue_id = qid;
      outcome := public.v2_publish_queue_item(qid);
      IF dropf IS NOT NULL THEN outcome := outcome || ' (dropped: ' || array_to_string(dropf, ', ') || ')'; END IF;
    ELSIF q.kind = 'new-firm' THEN  -- only the publish step creates a firm (F1.3.1)
      UPDATE v2_checker_queue SET status = 'passed' WHERE queue_id = qid;
      UPDATE v2_research_submissions SET status = 'Held: Checker confirmed; new firm waits for the publish step (F1.3.1)' WHERE submission_id = q.submission_id;
      outcome := 'Confirmed: new firm waits for the publish step (F1.3.1)';
    ELSIF q.table_name = 'v2_startups' THEN
      BEGIN
        UPDATE public.v2_startups t SET website_url = q.new_value->>'website_url',
            website_source = q.new_value->'website_source'
          WHERE t.startup_id = q.row_id AND coalesce(t.website_url,'') = '' RETURNING to_jsonb(t) INTO n;
        IF n IS NULL THEN
          UPDATE public.v2_checker_queue SET status = 'held-for-alex' WHERE queue_id = qid;
          UPDATE public.v2_research_submissions SET status = 'Held: startup website was filled meanwhile' WHERE submission_id = q.submission_id;
          outcome := 'Held for Alex: startup website was filled meanwhile';
        ELSE
          UPDATE public.v2_checker_queue SET status = 'passed' WHERE queue_id = qid;
          UPDATE public.v2_research_submissions SET status = 'Accepted' WHERE submission_id = q.submission_id;
          res := jsonb_build_object('website_url', n->>'website_url');
          outcome := 'Confirmed: website filled';
        END IF;
      EXCEPTION WHEN unique_violation THEN
        UPDATE public.v2_checker_queue SET status = 'failed' WHERE queue_id = qid;
        UPDATE public.v2_research_submissions SET status = 'Rejected: another startup already has this website domain' WHERE submission_id = q.submission_id;
        outcome := 'Rejected: another startup already has this website domain';
      END;
    ELSE  -- changed-key-fact or empty firm field: never overwrite an existing value (P15)
      SELECT to_jsonb(f) INTO o FROM v2_firms f WHERE firm_id = q.firm_id;
      IF o IS NULL THEN RAISE EXCEPTION 'v2_checker: firm % not found', q.firm_id; END IF;
      FOR k, v IN SELECT * FROM jsonb_each(q.new_value) WHERE key = ANY(firm_fields) LOOP
        IF o->k IS NOT NULL AND o->k <> 'null'::jsonb AND (o->>k) IS DISTINCT FROM (v#>>'{}') THEN conflicts := conflicts || k; END IF;
      END LOOP;
      IF cardinality(conflicts) > 0 THEN
        UPDATE v2_checker_queue SET status = 'held-for-alex' WHERE queue_id = qid;
        UPDATE v2_research_submissions SET status = 'Held: Checker confirmed; changed key fact waits for Alex (P15)' WHERE submission_id = q.submission_id;
        outcome := 'Held for Alex: would overwrite existing key fact ('||array_to_string(conflicts,', ')||')';
      ELSE
        EXECUTE format('UPDATE public.v2_firms t SET (%s) = (SELECT %s FROM jsonb_populate_record(NULL::public.v2_firms, $1)), last_checked_date = current_date WHERE firm_id = $2 RETURNING to_jsonb(t)',
          (SELECT string_agg(format('%I',x),',') FROM jsonb_object_keys(q.new_value) x), (SELECT string_agg(format('%I',x),',') FROM jsonb_object_keys(q.new_value) x)) INTO n USING q.new_value, q.firm_id;
        UPDATE v2_checker_queue SET status = 'passed' WHERE queue_id = qid;
        UPDATE v2_research_submissions SET status = 'Accepted' WHERE submission_id = q.submission_id;
        res := (SELECT jsonb_object_agg(x, n->x) FROM jsonb_object_keys(q.new_value) x);
        outcome := 'Confirmed: applied (fields were empty or unchanged)';
      END IF;
    END IF;
    INSERT INTO v2_checker_verdicts (queue_id, submission_id, actor, verdict, reason, sources, outcome)
      VALUES (qid, q.submission_id, bot, verdict, reason, sources, outcome);
    INSERT INTO v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
      VALUES (bot, q.firm_id, coalesce((SELECT target_box FROM v2_research_submissions WHERE submission_id=q.submission_id),'?'), q.table_name, q.row_id, q.submission_id,
              CASE WHEN res IS NOT NULL THEN (SELECT jsonb_object_agg(x, o->x) FROM jsonb_object_keys(q.new_value) x) ELSE q.old_value END,
              jsonb_build_object('checker_verdict',verdict,'outcome',outcome,'queue_id',qid,'reason',reason,'sources',sources,'applied',res)
                || CASE WHEN dropped IS NOT NULL THEN jsonb_build_object('dropped',dropped) ELSE '{}'::jsonb END, left(CASE WHEN verdict = 'reject' THEN 'Rejected: Checker: '||reason
                   WHEN outcome LIKE 'Confirmed: applied%' OR q.kind IN ('name-only','accepted-item') THEN 'Accepted'
                   ELSE 'Blocked: Checker confirmed; '||outcome END, 500));
    IF p_dry_run THEN RAISE EXCEPTION 'v2_dry_run_rollback'; END IF;
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'v2_dry_run_rollback' THEN RETURN jsonb_build_object('ok',false,'error',SQLERRM); END IF;
  END;
  RETURN jsonb_strip_nulls(jsonb_build_object('ok',true,'bot_id',bot,'dry_run',p_dry_run,'queue_id',qid,'kind',q.kind,'verdict',verdict,'outcome',outcome,
    'applied',res,'dropped',dropped,'note',CASE WHEN p_dry_run THEN 'dry run: nothing saved' END));
END $function$
$fn$;
end
$mig$;
