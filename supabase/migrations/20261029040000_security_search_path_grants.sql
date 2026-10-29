-- Security advisor fixes (Alex approved #14, 2026-10-28).
-- 1) Fixed search_path on every public function that had none (advisor: function_search_path_mutable).
--    public, extensions = the same places these functions already looked; _checker_link_opens uses extensions.http_get.
--    Each line is skipped if the function does not exist (test database built from migrations).

do $$ begin if to_regprocedure('public._checker_check_n(text,text)') is not null then execute 'alter function public._checker_check_n(text,text) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._checker_host(text)') is not null then execute 'alter function public._checker_host(text) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._checker_item_text(text,jsonb)') is not null then execute 'alter function public._checker_item_text(text,jsonb) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._checker_link_opens(text,jsonb)') is not null then execute 'alter function public._checker_link_opens(text,jsonb) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._checker_payload_items(jsonb)') is not null then execute 'alter function public._checker_payload_items(jsonb) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._checker_url_key(text)') is not null then execute 'alter function public._checker_url_key(text) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._court_register(text)') is not null then execute 'alter function public._court_register(text) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._deal_from_text(text)') is not null then execute 'alter function public._deal_from_text(text) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._dom(text)') is not null then execute 'alter function public._dom(text) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._door_key(text,jsonb)') is not null then execute 'alter function public._door_key(text,jsonb) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._edit_cols(text)') is not null then execute 'alter function public._edit_cols(text) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._enrich_section(text)') is not null then execute 'alter function public._enrich_section(text) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._firm_display_name_base(text)') is not null then execute 'alter function public._firm_display_name_base(text) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._fp_cases(text)') is not null then execute 'alter function public._fp_cases(text) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._fp_text(text)') is not null then execute 'alter function public._fp_text(text) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._fp_url(text)') is not null then execute 'alter function public._fp_url(text) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._fp_words(text)') is not null then execute 'alter function public._fp_words(text) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._fund_key(text)') is not null then execute 'alter function public._fund_key(text) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._host_is(text,text)') is not null then execute 'alter function public._host_is(text,text) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._jaccard(text[],text[])') is not null then execute 'alter function public._jaccard(text[],text[]) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._known_outlet(text)') is not null then execute 'alter function public._known_outlet(text) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._legal_key(text)') is not null then execute 'alter function public._legal_key(text) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._norm_txt(text)') is not null then execute 'alter function public._norm_txt(text) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._note_text(text,integer)') is not null then execute 'alter function public._note_text(text,integer) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._person_key(text)') is not null then execute 'alter function public._person_key(text) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._person_name_bad(text)') is not null then execute 'alter function public._person_name_bad(text) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._promo_money(jsonb)') is not null then execute 'alter function public._promo_money(jsonb) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._queue_name_key(text)') is not null then execute 'alter function public._queue_name_key(text) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._req_domain(text)') is not null then execute 'alter function public._req_domain(text) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._section_fields(text)') is not null then execute 'alter function public._section_fields(text) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._section_key(text)') is not null then execute 'alter function public._section_key(text) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._section_of_checklist(text)') is not null then execute 'alter function public._section_of_checklist(text) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._slugify(text)') is not null then execute 'alter function public._slugify(text) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._src_search_page(text)') is not null then execute 'alter function public._src_search_page(text) set search_path = public, extensions'; end if; end $$;
do $$ begin if to_regprocedure('public._timeline_key(text,text)') is not null then execute 'alter function public._timeline_key(text,text) set search_path = public, extensions'; end if; end $$;

-- 2) Internal SECURITY DEFINER helpers and trigger functions: not called by the site or app (no .rpc() in the repo,
--    no policy or view uses them). Only other definer functions or triggers call them, and those still work.
--    Triggers fire no matter who has EXECUTE. service_role keeps access.
do $$ begin if to_regprocedure('public._checker_exists(uuid,text,jsonb,text)') is not null then execute 'revoke execute on function public._checker_exists(uuid,text,jsonb,text) from public, anon, authenticated'; end if; end $$;
do $$ begin if to_regprocedure('public._checker_exists(uuid,text,jsonb,text)') is not null then execute 'grant execute on function public._checker_exists(uuid,text,jsonb,text) to service_role'; end if; end $$;
do $$ begin if to_regprocedure('public._enrich_cite_merge(uuid,text,uuid,text,text,bigint)') is not null then execute 'revoke execute on function public._enrich_cite_merge(uuid,text,uuid,text,text,bigint) from public, anon, authenticated'; end if; end $$;
do $$ begin if to_regprocedure('public._enrich_cite_merge(uuid,text,uuid,text,text,bigint)') is not null then execute 'grant execute on function public._enrich_cite_merge(uuid,text,uuid,text,text,bigint) to service_role'; end if; end $$;
do $$ begin if to_regprocedure('public._firm_by_name_key(text)') is not null then execute 'revoke execute on function public._firm_by_name_key(text) from public, anon, authenticated'; end if; end $$;
do $$ begin if to_regprocedure('public._firm_by_name_key(text)') is not null then execute 'grant execute on function public._firm_by_name_key(text) to service_role'; end if; end $$;
do $$ begin if to_regprocedure('public._firm_checks(uuid)') is not null then execute 'revoke execute on function public._firm_checks(uuid) from public, anon, authenticated'; end if; end $$;
do $$ begin if to_regprocedure('public._firm_checks(uuid)') is not null then execute 'grant execute on function public._firm_checks(uuid) to service_role'; end if; end $$;
do $$ begin if to_regprocedure('public._firm_checks_compute(uuid)') is not null then execute 'revoke execute on function public._firm_checks_compute(uuid) from public, anon, authenticated'; end if; end $$;
do $$ begin if to_regprocedure('public._firm_checks_compute(uuid)') is not null then execute 'grant execute on function public._firm_checks_compute(uuid) to service_role'; end if; end $$;
do $$ begin if to_regprocedure('public._investments_via_holding()') is not null then execute 'revoke execute on function public._investments_via_holding() from public, anon, authenticated'; end if; end $$;
do $$ begin if to_regprocedure('public._investments_via_holding()') is not null then execute 'grant execute on function public._investments_via_holding() to service_role'; end if; end $$;
do $$ begin if to_regprocedure('public._lab_live_pill(uuid,integer,integer,integer)') is not null then execute 'revoke execute on function public._lab_live_pill(uuid,integer,integer,integer) from public, anon, authenticated'; end if; end $$;
do $$ begin if to_regprocedure('public._lab_live_pill(uuid,integer,integer,integer)') is not null then execute 'grant execute on function public._lab_live_pill(uuid,integer,integer,integer) to service_role'; end if; end $$;
do $$ begin if to_regprocedure('public._mark_checked()') is not null then execute 'revoke execute on function public._mark_checked() from public, anon, authenticated'; end if; end $$;
do $$ begin if to_regprocedure('public._mark_checked()') is not null then execute 'grant execute on function public._mark_checked() to service_role'; end if; end $$;
do $$ begin if to_regprocedure('public._names_firm(uuid,text)') is not null then execute 'revoke execute on function public._names_firm(uuid,text) from public, anon, authenticated'; end if; end $$;
do $$ begin if to_regprocedure('public._names_firm(uuid,text)') is not null then execute 'grant execute on function public._names_firm(uuid,text) to service_role'; end if; end $$;
do $$ begin if to_regprocedure('public._pills_flush()') is not null then execute 'revoke execute on function public._pills_flush() from public, anon, authenticated'; end if; end $$;
do $$ begin if to_regprocedure('public._pills_flush()') is not null then execute 'grant execute on function public._pills_flush() to service_role'; end if; end $$;
do $$ begin if to_regprocedure('public._pills_mark()') is not null then execute 'revoke execute on function public._pills_mark() from public, anon, authenticated'; end if; end $$;
do $$ begin if to_regprocedure('public._pills_mark()') is not null then execute 'grant execute on function public._pills_mark() to service_role'; end if; end $$;
do $$ begin if to_regprocedure('public._registry_target(text)') is not null then execute 'revoke execute on function public._registry_target(text) from public, anon, authenticated'; end if; end $$;
do $$ begin if to_regprocedure('public._registry_target(text)') is not null then execute 'grant execute on function public._registry_target(text) to service_role'; end if; end $$;
do $$ begin if to_regprocedure('public._reviews_via_holding()') is not null then execute 'revoke execute on function public._reviews_via_holding() from public, anon, authenticated'; end if; end $$;
do $$ begin if to_regprocedure('public._reviews_via_holding()') is not null then execute 'grant execute on function public._reviews_via_holding() to service_role'; end if; end $$;
do $$ begin if to_regprocedure('public.research_queue_dedupe_trg()') is not null then execute 'revoke execute on function public.research_queue_dedupe_trg() from public, anon, authenticated'; end if; end $$;
do $$ begin if to_regprocedure('public.research_queue_dedupe_trg()') is not null then execute 'grant execute on function public.research_queue_dedupe_trg() to service_role'; end if; end $$;
