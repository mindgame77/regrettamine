-- Notify-me signups file a research job, the ready email sends once, and a valid
-- submission stamps the firm's report date. Bot payloads are never updated.
--
-- Why request 5 stayed unsent with no error: ondemand-notify skips any address
-- that is not TEST_ONLY_TO and does not call ondemand_mark_notified, so
-- notified_at and notify_error stay null and every tick retries the skip.
-- The row was also labeled ready_request (spend_kind = 'request') even though
-- firm_request_id is null, so the copy would have been "you asked us to add
-- this firm". ready_request is only for a real firm_requests row.
--
-- check_requests that share a visitor, firm, email and created_at with a
-- research_requests row (the hand route of job 5 / request 5) are linked and
-- marked notified here, so the signup is never emailed a second time. The
-- research_requests row is the one the outbox sends.

alter table public.check_requests
  add column if not exists job_id bigint references public.ondemand_jobs(id) on delete set null,
  add column if not exists research_request_id bigint references public.research_requests(id) on delete set null;
create index if not exists check_requests_research_request_idx
  on public.check_requests (research_request_id) where research_request_id is not null;

-- Link a signup to the job that already has the same email (one ready mail).
update public.check_requests c
   set research_request_id = r.id,
       job_id = r.job_id,
       notified_at = coalesce(c.notified_at, now()),
       status = 'done'
  from public.research_requests r
 where c.research_request_id is null
   and c.notified_at is null
   and c.email is not null
   and r.email is not null
   and c.firm_id = r.firm_id
   and c.anon_id is not distinct from r.anon_id
   and lower(c.email) = lower(r.email)
   and c.created_at = r.created_at
   and r.status = 'done';

-- A second notify with no balance must not insert a duplicate request row.
create or replace function public._ondemand_enqueue(p_firm uuid, p_qid text, p_balance uuid, p_kind text, p_email text, p_anon uuid)
returns bigint language plpgsql security definer set search_path = public as $$
declare j ondemand_jobs; q research_queue; front int; em text := lower(nullif(btrim(coalesce(p_email, '')), ''));
begin
  if em is not null and em !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then em := null; end if;
  select * into q from research_queue where registry_id = p_qid for update;
  select * into j from ondemand_jobs where firm_id = p_firm and status in ('queued', 'in_progress') for update;
  if j.id is null then
    insert into ondemand_jobs (firm_id, registry_id, status, missing_checks, claimed_at, claimed_by)
    values (p_firm, p_qid, case when q.status = 'claimed' and q.claimed_by = 'toxy-researcher-3' then 'in_progress' else 'queued' end,
            _ondemand_missing(p_firm), case when q.status = 'claimed' and q.claimed_by = 'toxy-researcher-3' then q.claimed_at end,
            case when q.status = 'claimed' and q.claimed_by = 'toxy-researcher-3' then q.claimed_by end)
    returning * into j;
  else
    update ondemand_jobs set missing_checks = _ondemand_missing(p_firm) where id = j.id;
  end if;
  if p_balance is null then
    update research_requests set email = coalesce(email, em)
     where id = (
       select id from research_requests
        where job_id = j.id and spend_kind = p_kind
          and (
            (auth.uid() is not null and user_id = auth.uid())
            or (auth.uid() is null and p_anon is not null and anon_id = p_anon)
            or (em is not null and email is not null and lower(email) = em)
          )
        order by (email is not null) desc, id desc limit 1);
    if not found then
      insert into research_requests (job_id, firm_id, balance_id, user_id, anon_id, email, status, spend_kind)
      values (j.id, p_firm, null, auth.uid(), case when auth.uid() is null then p_anon end, em,
              case when j.status = 'in_progress' then 'in_progress' else 'queued' end, p_kind);
    end if;
  else
    insert into research_requests (job_id, firm_id, balance_id, user_id, anon_id, email, status, spend_kind)
    values (j.id, p_firm, p_balance, auth.uid(), case when auth.uid() is null then p_anon end, em,
            case when j.status = 'in_progress' then 'in_progress' else 'queued' end, p_kind)
    on conflict (job_id, balance_id) do update set email = coalesce(research_requests.email, excluded.email);
  end if;
  select min(priority) into front from research_queue where status = 'queued' and registry_id <> p_qid;
  update research_queue set lane = 'paid', paid_at = coalesce(paid_at, now()),
    priority = least(priority, coalesce(front, priority + 1) - 1), bumped_at = now(),
    status = case when status = 'claimed' then status else 'queued' end,
    attempts = case when status in ('claimed', 'queued') then attempts else 0 end,
    retry_after = case when status = 'claimed' then retry_after else null end,
    claimed_by = case when status = 'claimed' then claimed_by end,
    claimed_at = case when status = 'claimed' then claimed_at end,
    updated_at = now()
  where registry_id = p_qid;
  return j.id;
end $$;
revoke all on function public._ondemand_enqueue(uuid, text, uuid, text, text, uuid) from public, anon, authenticated;

-- File one check_requests row. Firm already on the site: paid-lane job (researcher 3),
-- same shape as a hand-routed notify. Firm not on the site: research_queue registry_id
-- req-<id> (or req-c<id> when req-<id> is already a firm request), lane request.
-- The research_requests row owns the ready email. The signup is linked and marked
-- notified so it is never mailed again.
create or replace function public._check_request_file(p_id bigint) returns bigint
language plpgsql security definer set search_path = public as $$
declare c check_requests; fid uuid; qid text; em text; jid bigint; rid bigint; reg text; qn text;
begin
  select * into c from check_requests where id = p_id for update;
  if c.id is null or c.research_request_id is not null then return c.research_request_id; end if;
  em := lower(nullif(btrim(coalesce(c.email, '')), ''));
  if em is not null and em !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then em := null; end if;
  fid := c.firm_id;
  if fid is not null then qid := _firm_queue_id(fid); end if;
  if fid is not null and em is not null then
    select r.id, r.job_id into rid, jid from research_requests r
     where r.firm_id = fid and r.email is not null and lower(r.email) = em
     order by (r.status in ('queued', 'in_progress')) desc, r.id desc limit 1;
  end if;
  if rid is null and fid is not null and qid is not null and _ondemand_needed(fid) then
    jid := _ondemand_enqueue(fid, qid, null, 'request', em, c.anon_id);
    select r.id into rid from research_requests r
     where r.job_id = jid and r.spend_kind = 'request'
       and ((em is not null and lower(r.email) is not distinct from em) or (em is null and r.email is null)
            or (auth.uid() is null and c.anon_id is not null and r.anon_id = c.anon_id))
     order by r.id desc limit 1;
  elsif rid is null and fid is not null and qid is not null and em is not null and not _ondemand_needed(fid) then
    insert into ondemand_jobs (firm_id, registry_id, status, done_at)
    values (fid, qid, 'done', now()) returning id into jid;
    insert into research_requests (job_id, firm_id, balance_id, user_id, anon_id, email, status, spend_kind, done_at)
    values (jid, fid, null, c.user_id, c.anon_id, em, 'done', 'request', now()) returning id into rid;
  elsif fid is null then
    reg := 'req-' || c.id::text;
    if exists (select 1 from research_queue where registry_id = reg and coalesce(list_source, '') is distinct from 'check_request') then
      reg := 'req-c' || c.id::text;
    end if;
    qn := left(regexp_replace(btrim(coalesce(c.query, '')), '\s+', ' ', 'g'), 200);
    if length(qn) >= 1 then
      insert into research_queue (registry_id, name, priority, status, lane, paid_at, list_source)
      values (reg, qn, 0, 'queued', 'request', c.created_at, 'check_request')
      on conflict (registry_id) do nothing;
    end if;
  end if;
  if rid is not null then
    update research_requests set user_id = coalesce(user_id, c.user_id),
      anon_id = coalesce(anon_id, c.anon_id), email = coalesce(email, em) where id = rid;
    update check_requests set research_request_id = rid, job_id = coalesce(jid, job_id),
      notified_at = coalesce(notified_at, now()),
      status = case when (select status from research_requests where id = rid) = 'done' then 'done' else status end
     where id = c.id;
    update research_queue set status = 'skipped', lane = 'normal', paid_at = null,
      last_error = 'check request linked', updated_at = now()
     where list_source = 'check_request' and status = 'queued'
       and registry_id in ('req-' || c.id::text, 'req-c' || c.id::text);
  end if;
  return rid;
end $$;
revoke all on function public._check_request_file(bigint) from public, anon, authenticated;

-- Already-checked firm: keep the address and queue the ready email. No paid-lane reopen.
create or replace function public._ondemand_save_email(p_firm uuid, p_balance uuid, p_kind text, p_email text, p_anon uuid)
returns bigint language plpgsql security definer set search_path = public as $$
declare em text := lower(nullif(btrim(coalesce(p_email, '')), '')); qid text; jid bigint; rid bigint;
begin
  if em is null or em !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return null; end if;
  select r.id into rid from research_requests r
   where r.firm_id = p_firm and r.email is not null and lower(r.email) = em
     and ((p_balance is not null and r.balance_id = p_balance)
          or (auth.uid() is not null and r.user_id = auth.uid())
          or (auth.uid() is null and p_anon is not null and r.anon_id = p_anon))
   order by r.id desc limit 1;
  if rid is not null then return rid; end if;
  qid := _firm_queue_id(p_firm);
  if qid is null then return null; end if;
  insert into ondemand_jobs (firm_id, registry_id, status, done_at) values (p_firm, qid, 'done', now()) returning id into jid;
  insert into research_requests (job_id, firm_id, balance_id, user_id, anon_id, email, status, spend_kind, done_at)
  values (jid, p_firm, p_balance, auth.uid(), case when auth.uid() is null then p_anon end, em, 'done', p_kind, now())
  returning id into rid;
  return rid;
end $$;
revoke all on function public._ondemand_save_email(uuid, uuid, text, text, uuid) from public, anon, authenticated;

drop function if exists public.firm_page(text, uuid, boolean);
drop function if exists public.unlock_firm(text, uuid, boolean);

create or replace function public.unlock_firm(p_slug text, p_anon uuid, p_spend boolean default true, p_email text default null)
returns json language plpgsql security definer set search_path = public as $$
declare b public.check_balances := _balance(p_anon); f uuid; ix boolean; h text := _ip_hash(); ip_cap constant int := 4;
  need boolean; qid text; sk text; em text;
begin
  select id, indexable into f, ix from firms where slug = p_slug and deleted_at is null and published and not coalesce(is_test, false) and data_status = 'real';
  if f is null then return json_build_object('status','not_found'); end if;
  if coalesce((select sum(case when kind like 'spend_%' then 1 when kind = 'refund_ondemand' then -1 else 0 end) from check_events
               where balance_id = b.id and firm_id = f), 0) <= 0 then
    if not p_spend then return json_build_object('status','locked'); end if;
    need := _ondemand_needed(f);
    if need then qid := _firm_queue_id(f); end if;
    if not ix and qid is null then return json_build_object('status','unchecked'); end if;
    if b.free_left > 0 and auth.uid() is null and h is not null
       and (select count(*) from check_events where ip_hash = h and kind = 'spend_free' and created_at > now() - interval '30 days') >= ip_cap then
      return json_build_object('status','need_signup');
    end if;
    if b.free_left > 0 then
      update check_balances set free_left = free_left - 1, updated_at = now() where id = b.id;
      insert into check_events(balance_id, firm_id, kind, amount, ip_hash) values (b.id, f, 'spend_free', -1, case when auth.uid() is null then h end);
      sk := 'spend_free';
    elsif b.paid_left > 0 then
      update check_balances set paid_left = paid_left - 1, updated_at = now() where id = b.id;
      insert into check_events(balance_id, firm_id, kind, amount) values (b.id, f, 'spend_paid', -1);
      sk := 'spend_paid';
    elsif auth.uid() is null then return json_build_object('status','need_signup');
    else return json_build_object('status','out');
    end if;
    em := lower(nullif(btrim(coalesce((select email from auth.users where id = auth.uid()), p_email, '')), ''));
    if em is not null and em !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then em := null; end if;
    if need and qid is not null then
      perform _ondemand_enqueue(f, qid, b.id, sk, em, p_anon);
    elsif em is not null then
      perform _ondemand_save_email(f, b.id, sk, em, p_anon);
    end if;
  end if;
  return json_build_object('status','ok','details', public.firm_details(f));
end $$;
revoke all on function public.unlock_firm(text, uuid, boolean, text) from public, anon, authenticated;
grant execute on function public.unlock_firm(text, uuid, boolean, text) to service_role;

create or replace function public.firm_page(p_slug text, p_anon uuid, p_spend boolean default false, p_email text default null)
returns json language plpgsql security definer set search_path = public as $$
declare f firms; u json; open boolean; secs jsonb := '[]'; s page_sections; it jsonb; hero jsonb; q research_queue; qid text;
begin
  select * into f from firms where slug = p_slug and deleted_at is null and published and not coalesce(is_test, false) and data_status = 'real';
  if f.id is null then return json_build_object('status', 'not_found'); end if;
  u := unlock_firm(p_slug, p_anon, p_spend, p_email);
  open := u->>'status' = 'ok';
  if u->>'status' not in ('ok', 'locked') then return u; end if;
  if not open then
    select coalesce(jsonb_agg(jsonb_build_object('label', hero_label, 'value', hero_value, 'anchor', section,
        'src', _src('firm_profile_facts', id)) order by section desc, sort_order), '[]') into hero
      from firm_profile_facts where firm_id = f.id and hero_label is not null and exists (select 1 from fact_sources where fact_type = 'firm_profile_facts' and fact_id = firm_profile_facts.id);
    qid := _firm_queue_id(f.id);
    if qid is not null then select * into q from research_queue where registry_id = qid; end if;
    if not f.indexable and jsonb_array_length(hero) = 0 then
      select coalesce(jsonb_agg(jsonb_build_object('label', l, 'value', v, 'anchor', 'overview', 'src', '[]'::jsonb) order by o), '[]') into hero
        from (values (1, 'HQ', f.hq), (2, 'SEC CRD', nullif(q.sec_crd, '')), (3, 'LEI', nullif(q.lei, ''))) x(o, l, v) where v is not null;
    end if;
    return json_build_object('status', 'ok', 'open', false, 'locked', u->>'status', 'unchecked', not f.indexable,
      'firm', json_build_object('slug', f.slug, 'name', coalesce(f.display_name, f.name), 'sec_name', coalesce(f.legal_name, f.name), 'short_name', f.short_name, 'hq', f.hq),
      'hero', hero, 'sections', '[]'::json, 'done', _firm_checks_done(f.id),
      'checks', (select json_agg(json_build_object('n', n, 'title', title, 'descr', descr, 'state', null, 'count', null, 'searched_at', null,
          'items', null, 'itemized', null) order by n) from firm_check_rows where firm_id = f.id),
      'queue', q.status, 'started_at', case when q.status = 'claimed' then q.claimed_at end, 'details', null, 'outline', null,
      'ondemand', _ondemand_view(f.id, p_anon));
  end if;
  for s in select * from page_sections where enabled order by sort_order loop
    it := _sec_items(s.key, f.id);
    continue when jsonb_array_length(it) = 0;
    secs := secs || jsonb_build_object('key', s.key, 'title', s.title, 'subtitle', s.subtitle, 'renderer', s.renderer,
      'count', jsonb_array_length(it), 'unit', case when jsonb_array_length(it) = 1 then s.unit_one else s.unit_many end,
      'teaser', it->0->>'head', 'items', it);
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('label', hero_label, 'value', hero_value, 'anchor', section,
      'src', _src('firm_profile_facts', id)) order by section desc, sort_order), '[]') into hero
    from firm_profile_facts where firm_id = f.id and hero_label is not null and exists (select 1 from fact_sources where fact_type = 'firm_profile_facts' and fact_id = firm_profile_facts.id);
  qid := _firm_queue_id(f.id);
  if qid is not null then select * into q from research_queue where registry_id = qid; end if;
  return json_build_object('status', 'ok', 'open', true, 'unchecked', false, 'done', _firm_checks_done(f.id),
    'firm', json_build_object('slug', f.slug, 'name', coalesce(f.display_name, f.name), 'sec_name', coalesce(f.legal_name, f.name), 'short_name', f.short_name, 'hq', f.hq),
    'hero', hero, 'sections', secs,
    'checks', (select json_agg(json_build_object('n', n, 'title', title, 'descr', descr, 'state', state, 'count', count_label, 'searched_at', searched_at,
        'items', (select coalesce(json_agg(json_build_object('title', i.title, 'year', i.yr, 'status', i.status, 'note', i.note, 'who', i.who) order by i.yr desc nulls last, i.title), '[]') from check_findings(source_submission) i where i.k = n),
        'itemized', (select count(*) from check_findings(source_submission) i where i.k = n)) order by n) from firm_check_rows where firm_id = f.id),
    'queue', q.status, 'started_at', case when q.status = 'claimed' then q.claimed_at end,
    'details', u->'details', 'outline', null, 'ondemand', _ondemand_view(f.id, p_anon));
end $$;
revoke all on function public.firm_page(text, uuid, boolean, text) from public;
grant execute on function public.firm_page(text, uuid, boolean, text) to anon, authenticated, service_role;

create or replace function public.notify_when_checked(p_slug text, p_email text, p_anon uuid)
returns json language plpgsql security definer set search_path = public as $$
declare f firms; em text; rid bigint;
begin
  select * into f from firms where slug = p_slug and deleted_at is null and published and not coalesce(is_test, false) and data_status = 'real';
  if f.id is null then return json_build_object('status', 'not_found'); end if;
  em := lower(trim(coalesce((select email from auth.users where id = auth.uid()), p_email, '')));
  if em !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(em) > 200 then return json_build_object('status', 'bad_email'); end if;
  if auth.uid() is null and p_anon is null then return json_build_object('status', 'no_visitor'); end if;
  update research_requests set email = em
   where id = (select id from research_requests where firm_id = f.id and status in ('queued', 'in_progress')
                 and ((auth.uid() is not null and user_id = auth.uid()) or (auth.uid() is null and anon_id = p_anon)) order by id desc limit 1);
  if found then return json_build_object('status', 'ok'); end if;
  if exists (select 1 from check_requests where firm_id = f.id and lower(email) = em and (notified_at is null or research_request_id is not null)) then
    return json_build_object('status', 'ok'); end if;
  if (select count(*) from check_requests where created_at > now() - interval '1 hour'
       and (user_id = auth.uid() or (auth.uid() is null and anon_id = p_anon))) >= 10 then
    return json_build_object('status', 'rate_limited'); end if;
  insert into check_requests (query, email, anon_id, user_id, firm_id, status)
    values (f.name, em, p_anon, auth.uid(), f.id, 'running') returning id into rid;
  perform _check_request_file(rid);
  return json_build_object('status', 'ok');
end $$;

create or replace function public.request_check(p_query text, p_email text, p_anon uuid)
returns void language plpgsql security definer set search_path = public as $$
declare t text := lower(btrim(coalesce(p_query, ''))); fid uuid; rid bigint;
begin
  insert into check_requests(query, email, anon_id, user_id) values (trim(p_query), nullif(trim(p_email),''), p_anon, auth.uid()) returning id into rid;
  if t = '' then return; end if;
  if (select count(*) from check_requests where created_at > now() - interval '1 hour'
       and ((auth.uid() is not null and user_id = auth.uid()) or (auth.uid() is null and anon_id = p_anon))) > 10 then return; end if;
  select f.id into fid from firms f
   where f.published and f.deleted_at is null and not coalesce(f.is_test, false) and f.data_status = 'real'
     and (lower(coalesce(f.display_name, f.name)) = t or lower(f.name) = t or f.slug = t or lower(coalesce(f.short_name, '')) = t
          or exists (select 1 from firm_aliases a where a.firm_id = f.id and lower(a.alias) = t))
   order by f.indexable, f.id limit 1;
  if fid is not null then update check_requests set firm_id = fid where id = rid; end if;
  perform _check_request_file(rid);
end $$;

-- A request-lane row that belongs to a check signup is not a firm_requests row.
create or replace function public.firm_request_done_trg()
returns trigger language plpgsql security definer set search_path = public as $$
declare q research_queue; v_req bigint;
begin
  if not new.valid or new.registry_id !~ '^req-[0-9]+$' then return null; end if;
  begin
    select * into q from research_queue where registry_id = new.registry_id;
    if q.lane is distinct from 'request' or q.list_source = 'check_request' then return null; end if;
    v_req := substring(new.registry_id from 5)::bigint;
    if (select status from firm_requests where firm_requests.id = v_req) = 'open' then perform firm_request_link(v_req, new.registry_id); end if;
    update research_queue set lane = 'normal', paid_at = null, updated_at = now() where registry_id = new.registry_id and lane = 'request';
  exception when others then
    raise warning 'firm_request_done: submission % registry %: %', new.id, new.registry_id, sqlerrm;
  end;
  return null;
end $$;
revoke all on function public.firm_request_done_trg() from public, anon, authenticated;

-- Research for a check-signup queue row landed: attach it to the new page (paid job if checks
-- are still missing, otherwise a done request so the ready email can go out).
create or replace function public.check_request_done_trg()
returns trigger language plpgsql security definer set search_path = public as $$
declare q research_queue; v_id bigint; fid uuid;
begin
  if not new.valid then return null; end if;
  begin
    select * into q from research_queue where registry_id = new.registry_id;
    if q.list_source is distinct from 'check_request' then return null; end if;
    v_id := substring(q.registry_id from '([0-9]+)$')::bigint;
    select id into fid from firms
     where registry_id = coalesce(_registry_target(new.registry_id), new.registry_id) and deleted_at is null
     order by created_at limit 1;
    if fid is not null then update check_requests set firm_id = fid where id = v_id and firm_id is null; end if;
    perform _check_request_file(v_id);
  exception when others then
    raise warning 'check_request_done: submission % registry %: %', new.id, new.registry_id, sqlerrm;
  end;
  return null;
end $$;
revoke all on function public.check_request_done_trg() from public, anon, authenticated;
drop trigger if exists zz_check_request_done on public.research_submissions;
create trigger zz_check_request_done after insert on public.research_submissions
  for each row execute function public.check_request_done_trg();

-- ready_request only when this row is a "Request this firm" signup. A notify on a firm
-- that is already on the site uses the ready email ("your check is ready").
create or replace function public.ondemand_outbox(p_limit int default 50)
returns table(id bigint, kind text, email text, name text, slug text)
language sql stable security definer set search_path = public as $$
  select * from (
    select r.id,
           case when r.status = 'refunded' then 'refund'
                when r.spend_kind = 'request' and r.firm_request_id is not null then 'ready_request'
                else 'ready' end kind,
           r.email, coalesce(f.display_name, f.name) name, f.slug
      from research_requests r join firms f on f.id = r.firm_id
     where r.status in ('done', 'refunded') and r.email is not null and r.notified_at is null and r.notify_error is null
       and f.published and f.deleted_at is null and f.data_status = 'real' and not coalesce(f.is_test, false)
    union all
    select e.id, 'received', e.email, q.name, null::text
      from firm_request_emails e join firm_requests q on q.id = e.request_id
     where e.received_notified_at is null and e.notify_error is null and e.research_request_id is null
       and e.created_at > now() - interval '2 days') x
  order by kind = 'received', id limit greatest(1, least(coalesce(p_limit, 50), 200))
$$;
revoke all on function public.ondemand_outbox(int) from public, anon, authenticated;
grant execute on function public.ondemand_outbox(int) to service_role;

create or replace function public.ondemand_mark_notified(p_id bigint, p_error text default null, p_kind text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_kind = 'received' then
    update firm_request_emails set received_notified_at = case when p_error is null then now() end, notify_error = left(p_error, 500) where id = p_id;
  else
    update research_requests set notified_at = case when p_error is null then now() end, notify_error = left(p_error, 500) where id = p_id;
    update check_requests set notified_at = coalesce(notified_at, case when p_error is null then now() end),
      status = case when p_error is null then 'done' else status end
     where research_request_id = p_id;
  end if;
end $$;
revoke all on function public.ondemand_mark_notified(bigint, text, text) from public, anon, authenticated;
grant execute on function public.ondemand_mark_notified(bigint, text, text) to service_role;

-- The old notify-checks worker must not mail a signup whose job already owns the email.
create or replace function public.ready_check_requests() returns table(id bigint, email text, query text, slug text, name text)
language sql stable security definer set search_path = public as $$
  select r.id, r.email, r.query, f.slug, f.name
  from check_requests r
  join lateral (
    select fm.* from firms fm
    where fm.published and fm.deleted_at is null and (
      fm.id = r.firm_id or lower(fm.name) = lower(trim(r.query)) or lower(fm.slug) = lower(trim(r.query))
      or lower(coalesce(fm.short_name,'')) = lower(trim(r.query))
      or exists (select 1 from vc_aliases a where a.firm_id = fm.id and lower(a.value) = lower(trim(r.query))))
    order by (fm.id = r.firm_id) desc limit 1) f on true
  where r.email is not null and r.notified_at is null and r.research_request_id is null
    and r.status in ('queued','running','done')
    and _firm_checks_done(f.id) >= 10
  order by r.created_at limit 50
$$;
revoke all on function public.ready_check_requests() from public, anon, authenticated;
grant execute on function public.ready_check_requests() to service_role;

-- A valid submission copies firm.generated_at onto firms.report_date and refreshes updated_at
-- (sitemap lastmod). The submission row, including payload, is not written.
create or replace function public.stamp_firm_report_trg() returns trigger
language plpgsql security definer set search_path = public as $$
declare t text; d date;
begin
  if not new.valid then return null; end if;
  begin
    t := coalesce(_registry_target(new.registry_id), new.registry_id);
    d := substring(new.payload->'firm'->>'generated_at' from '^\d{4}-\d{2}-\d{2}')::date;
    update firms set
      report_date = case when d is not null and (report_date is null or d > report_date) then d else report_date end,
      updated_at = now()
     where deleted_at is null and registry_id = t;
  exception when others then
    raise warning 'stamp_firm_report: submission %: %', new.id, sqlerrm;
  end;
  return null;
end $$;
revoke all on function public.stamp_firm_report_trg() from public, anon, authenticated;
drop trigger if exists zz_stamp_firm_report on public.research_submissions;
create trigger zz_stamp_firm_report after insert on public.research_submissions
  for each row execute function public.stamp_firm_report_trg();

-- Pages whose report date was never copied off a valid submission.
update public.firms f
   set report_date = s.gen, updated_at = now()
  from (
    select distinct on (reg) reg, gen
      from (
        select coalesce(_registry_target(registry_id), registry_id) as reg,
               substring(payload->'firm'->>'generated_at' from '^\d{4}-\d{2}-\d{2}')::date as gen,
               received_at, id
          from research_submissions
         where valid and payload->'firm'->>'generated_at' ~ '^\d{4}-\d{2}-\d{2}'
      ) x
     order by reg, received_at desc, id desc
  ) s
 where f.registry_id = s.reg
   and f.deleted_at is null
   and not coalesce(f.is_test, false)
   and f.report_date is null
   and s.gen is not null;
