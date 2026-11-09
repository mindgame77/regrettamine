-- Disable and remove the Muse trusted publication path.
-- Later external-muse-bot submissions go back to the Checker queue.
-- Rows already published stay. Nothing is deleted. Other bots are unchanged.
-- No settings row and no control panel. Apply 20261109030000_v2_muse_trusted_publish.sql again to turn the path back on.
do $mig$
declare
  d text;
  n text;
  key_old text := $key_old$  INSERT INTO public.v2_bot_keys (bot_name, key_hash) VALUES (bot, ik.key_hash)
    ON CONFLICT (bot_name) DO UPDATE SET key_hash = EXCLUDED.key_hash RETURNING * INTO bk;
  muse := bk.bot_key_id = 322 AND bot = 'external-muse-bot';$key_old$;
  key_new text := $key_new$  INSERT INTO public.v2_bot_keys (bot_name, key_hash) VALUES (bot, ik.key_hash)
    ON CONFLICT (bot_name) DO UPDATE SET key_hash = EXCLUDED.key_hash RETURNING * INTO bk;$key_new$;
  decl_old text := $decl_old$empty_fill boolean; ft_id smallint; muse boolean := false; qid bigint; pub text; flag_reason text;$decl_old$;
  decl_new text := $decl_new$empty_fill boolean; ft_id smallint;$decl_new$;
  loop_old text := $loop_old$    idx := idx + 1; reason := NULL; sid := NULL; newid := NULL; q_kind := NULL; res := NULL; qid := NULL; pub := NULL; flag_reason := NULL;$loop_old$;
  loop_new text := $loop_new$    idx := idx + 1; reason := NULL; sid := NULL; newid := NULL; q_kind := NULL; res := NULL;$loop_new$;
  exc_old text := $exc_old$      EXCEPTION
        WHEN unique_violation OR exclusion_violation THEN
          IF muse THEN flag_reason := left(SQLERRM, 300); ELSE reason := left(SQLERRM, 300); END IF;
        WHEN others THEN
          IF muse AND SQLERRM ILIKE '%duplicate%' THEN flag_reason := left(SQLERRM, 300);
          ELSE reason := left(SQLERRM, 300); END IF;
      END;
    END IF;

    -- muse-trusted-publish: a duplicate-guard collision is held, not merged and not published.
    IF flag_reason IS NOT NULL THEN
      UPDATE public.v2_research_submissions SET status = 'Held: '||flag_reason WHERE submission_id = sid;
      INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, submission_id, new_value, result)
        VALUES (bot, fid, coalesce(box,'?'), coalesce(tbl,'?'), sid, it, 'Blocked: held, '||flag_reason);
      held := held + 1;
      results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Held: '||flag_reason,'table',tbl);
      CONTINUE;
    END IF;

    IF reason IS NOT NULL THEN$exc_old$;
  exc_new text := $exc_new$      EXCEPTION WHEN others THEN reason := left(SQLERRM, 300); END;
    END IF;

    IF reason IS NOT NULL THEN$exc_new$;
  acc_old text := $acc_old$    ELSE  -- 011: every accepted item goes live only after the Checker passes it (Checker-first, R4.1; covers 010 LP rows too)
      q_kind := 'accepted-item';
      INSERT INTO public.v2_checker_queue (submission_id, firm_id, kind, table_name, row_id, new_value) VALUES (sid, fid, 'accepted-item', tbl, newid, res)
        RETURNING queue_id INTO qid;
      -- muse-trusted-publish: external-muse-bot key 322 only. Source wording stays Muse's.
      -- v2_publish_queue_item still applies archived, shown, and the other publication rules.
      IF muse THEN
        UPDATE public.v2_checker_queue SET status = 'passed'
         WHERE queue_id = qid AND submission_id = sid AND kind = 'accepted-item' AND status = 'open';
        IF NOT FOUND THEN
          flag_reason := 'Muse item was not an open accepted-item';
        ELSE
          BEGIN
            pub := public.v2_publish_queue_item(qid);
          EXCEPTION WHEN others THEN
            pub := NULL;
            flag_reason := left(SQLERRM, 300);
          END;
          IF flag_reason IS NULL AND coalesce(pub, '') NOT LIKE 'Confirmed:%' THEN
            flag_reason := coalesce(left(pub, 300), 'publish returned nothing');
          END IF;
        END IF;
        IF flag_reason IS NOT NULL THEN
          UPDATE public.v2_checker_queue SET status = 'held-for-alex'
           WHERE queue_id = qid AND submission_id = sid AND status = 'passed';
          UPDATE public.v2_research_submissions SET status = 'Held: '||flag_reason WHERE submission_id = sid;
          INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, new_value, result)
            VALUES ('v2_research_submit', fid, box, tbl, newid, sid, jsonb_build_object('queue_id', qid, 'bot_key_id', bk.bot_key_id), 'Blocked: held, '||flag_reason);
          held := held + 1;
          results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Held: '||flag_reason,'table',tbl,'row_id',newid,'checker_queued','held-for-alex');
          CONTINUE;
        END IF;
        INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, new_value, result)
          VALUES ('v2_research_submit', fid, box, tbl, newid, sid, jsonb_build_object('queue_id', qid, 'publish', pub, 'bot_key_id', bk.bot_key_id), 'Accepted: published on the Muse trusted path');
      END IF;
    END IF;
    acc := acc + 1;
    results := results || jsonb_strip_nulls(jsonb_build_object('index',idx,'submission_id',sid,'status','Accepted','table',tbl,'row_id',newid,'checker_queued',CASE WHEN pub IS NOT NULL THEN NULL ELSE q_kind END,
      'note',CASE
        WHEN pub IS NOT NULL AND (p->>'source_level') = '4' THEN 'published on the Muse trusted path; L4: kept archived (R2)'
        WHEN pub IS NOT NULL THEN 'published on the Muse trusted path'
        WHEN (p->>'source_level') = '4' THEN 'L4: kept archived (R2)'
      END));$acc_old$;
  acc_new text := $acc_new$    ELSE  -- 011: every accepted item goes live only after the Checker passes it (Checker-first, R4.1; covers 010 LP rows too)
      q_kind := 'accepted-item';
      INSERT INTO public.v2_checker_queue (submission_id, firm_id, kind, table_name, row_id, new_value) VALUES (sid, fid, 'accepted-item', tbl, newid, res);
    END IF;
    acc := acc + 1;
    results := results || jsonb_strip_nulls(jsonb_build_object('index',idx,'submission_id',sid,'status','Accepted','table',tbl,'row_id',newid,'checker_queued',q_kind,
      'note',CASE WHEN (p->>'source_level')='4' THEN 'L4: kept archived (R2)' END));$acc_new$;
begin
  if to_regprocedure('public.v2_research_submit(uuid,jsonb,boolean)') is null then
    raise notice 'v2_research_submit missing, skipped';
    return;
  end if;

  select pg_get_functiondef('public.v2_research_submit(uuid,jsonb,boolean)'::regprocedure) into d;
  if position('published on the Muse trusted path' in d) = 0 then
    raise notice 'v2_research_submit Muse trusted path already absent';
    return;
  end if;

  if length(d) - length(replace(d, key_old, '')) <> length(key_old)
     or length(d) - length(replace(d, decl_old, '')) <> length(decl_old)
     or length(d) - length(replace(d, loop_old, '')) <> length(loop_old)
     or length(d) - length(replace(d, exc_old, '')) <> length(exc_old)
     or length(d) - length(replace(d, acc_old, '')) <> length(acc_old) then
    raise exception 'v2_research_submit: Muse trusted path undo anchor missing or not unique';
  end if;

  n := replace(replace(replace(replace(replace(d, key_old, key_new), decl_old, decl_new), loop_old, loop_new), exc_old, exc_new), acc_old, acc_new);
  if n = d
     or position('published on the Muse trusted path' in n) > 0
     or position('muse-trusted-publish' in n) > 0
     or position('muse := bk.bot_key_id = 322 AND bot = ''external-muse-bot''' in n) > 0
     or position(acc_new in n) = 0 then
    raise exception 'v2_research_submit: Muse trusted path undo did not apply';
  end if;
  execute n;
end
$mig$;
