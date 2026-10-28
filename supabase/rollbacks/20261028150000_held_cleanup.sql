-- Restores held rows from home_held_backup and removes homes added by the cleanup.
-- Does not delete home_held_backup.

insert into public.firm_profile_facts
select rec.* from public.home_held_backup b,
  lateral jsonb_populate_record(null::public.firm_profile_facts, b.row_data->'row') rec
where b.table_name = 'firm_profile_facts'
on conflict (id) do nothing;

insert into public.fund_people
select rec.* from public.home_held_backup b,
  lateral jsonb_populate_record(null::public.fund_people, b.row_data->'row') rec
where b.table_name = 'fund_people'
on conflict (id) do nothing;

insert into public.regulatory_records
select rec.* from public.home_held_backup b,
  lateral jsonb_populate_record(null::public.regulatory_records, b.row_data->'row') rec
where b.table_name = 'regulatory_records'
on conflict (id) do nothing;

insert into public.legal_matter_firms
select rec.* from public.home_held_backup b,
  lateral jsonb_populate_record(null::public.legal_matter_firms, b.row_data->'row') rec
where b.table_name = 'legal_matter_firms'
on conflict (id) do nothing;

insert into bots.firm_lps
select rec.* from public.home_held_backup b,
  lateral jsonb_populate_record(null::bots.firm_lps, b.row_data->'row') rec
where b.table_name = 'firm_lps'
on conflict (id) do nothing;

delete from public.funds u using public.home_held_backup b
where b.inserted_table = 'funds' and b.inserted_id = u.id;
delete from public.firm_people_roles u using public.home_held_backup b
where b.inserted_table = 'firm_people_roles' and b.inserted_id = u.id;
delete from public.firm_legal_items u using public.home_held_backup b
where b.inserted_table = 'firm_legal_items' and b.inserted_id = u.id;
delete from public.firm_profile_facts u using public.home_held_backup b
where b.inserted_table = 'firm_profile_facts' and b.inserted_id = u.id;

delete from public.rejected_items r
using public.home_held_backup b
where r.firm_id = b.firm_id and r.kind = b.kind
  and (r.item_key = b.item_key or r.item_key = 'name:' || public._norm_txt(coalesce(b.row_data->'row'->>'label', b.row_data->'row'->>'full_name', b.row_data->'row'->>'title', b.row_data->'row'->>'lp_name', '')));

drop function if exists public.lab_held_cleanup(boolean);

create or replace function public._checker_decide(
  p_firm uuid, p_section text, p_f jsonb, p_url text, p_check int, p_probes jsonb)
returns table(lvl smallint, outcome text, reason text)
language plpgsql stable security definer set search_path = public as $$
declare base smallint; blob text; who text; host text; firm_dom text; company_key text;
begin
  if public.source_tier(p_url) is null then
    lvl := null; outcome := 'failure'; reason := 'link is not real (missing, not http, or a search/chat page)';
    return next; return;
  end if;
  if p_probes is not null and (p_probes ? p_url) and (p_probes->>p_url) in ('false', 'f') then
    lvl := null; outcome := 'failure'; reason := 'dead link';
    return next; return;
  end if;
  if p_check is not null and p_url ~* 'opensanctions\.org' and p_check not in (1, 2, 10) then
    lvl := null; outcome := 'failure'; reason := 'OpenSanctions is only a source inside checks 1, 2 and 10';
    return next; return;
  end if;
  base := public._source_level(p_url, p_firm, p_check);
  blob := concat_ws(' ', p_f->>'headline', p_f->>'snippet', p_f->>'event', p_f->>'quote', p_f->>'title', p_f->>'value', p_f->>'name', p_f->>'who');
  who := lower(btrim(coalesce(p_f->>'who', p_f->>'author', '')));
  host := public._dom(p_url);
  select nullif(lower(primary_domain), '') into firm_dom from firms where id = p_firm;

  if p_section = 'legal' or public._court_register(p_url) then
    if public._court_register(p_url) or base = 1 then
      lvl := 1; outcome := 'published'; reason := null;
    else
      lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: lawsuit source is not CourtListener, PACER, or uscourts.gov';
    end if;
    return next; return;
  end if;

  if p_section = 'founders' then
    if who in ('', 'anonymous', 'anon', 'unknown')
       and coalesce(p_f->>'quote', '') !~* 'founder|i founded'
       and coalesce(p_f->>'type', '') !~* 'founder' then
      lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: anonymous, no founder claim';
      return next; return;
    end if;
    if not (public._host_is(p_url, 'reddit.com') or public._host_is(p_url, 'x.com')
            or public._host_is(p_url, 'twitter.com') or public._host_is(p_url, 'linkedin.com')) then
      lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: review is not from Reddit, X, or LinkedIn';
      return next; return;
    end if;
    if coalesce(btrim(p_f->>'quote'), '') = '' then
      lvl := null; outcome := 'failure'; reason := 'review is not copied word for word';
      return next; return;
    end if;
    if not public._names_firm(p_firm, blob) then
      lvl := null; outcome := 'failure'; reason := 'off-topic: review does not name the firm';
      return next; return;
    end if;
    if who !~* 'founder' and coalesce(p_f->>'quote', '') !~* 'founder|i founded'
       and coalesce(p_f->>'type', '') !~* 'founder' then
      lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: writer does not say they are a founder';
      return next; return;
    end if;
    lvl := 2; outcome := 'published'; reason := null;
    return next; return;
  end if;

  if p_section in ('press', 'timeline') then
    if public._known_outlet(p_url) then
      if public._names_firm(p_firm, blob) then
        lvl := 2; outcome := 'published'; reason := null;
      else
        lvl := null; outcome := 'failure'; reason := 'off-topic: story does not name the firm';
      end if;
    else
      lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: unknown outlet, not shown';
    end if;
    return next; return;
  end if;

  if p_section = 'people' then
    if public._host_is(p_url, 'sec.gov') or public._host_is(p_url, 'adviserinfo.sec.gov') then
      lvl := 1; outcome := 'published'; reason := null;
    elsif firm_dom is not null and (host = firm_dom or host like '%.' || firm_dom) then
      lvl := 2; outcome := 'published'; reason := null;
    elsif public._host_is(p_url, 'linkedin.com') and p_url ~* '/in/' then
      lvl := 2; outcome := 'published'; reason := null;
    else
      lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: people source is not Form ADV, the team page, or that person''s LinkedIn history';
    end if;
    return next; return;
  end if;

  if p_section = 'deals' then
    if public._host_is(p_url, 'sec.gov') then
      lvl := 2; outcome := 'published'; reason := null;
    elsif public._known_outlet(p_url) then
      if public._names_firm(p_firm, blob) then
        lvl := 2; outcome := 'published'; reason := null;
      else
        lvl := null; outcome := 'failure'; reason := 'off-topic: deal story does not name the firm';
      end if;
    else
      company_key := lower(regexp_replace(coalesce(p_f->>'company', ''), '[^a-zA-Z0-9]', '', 'g'));
      if length(company_key) >= 3 and position(company_key in lower(regexp_replace(coalesce(host, ''), '[^a-zA-Z0-9]', '', 'g'))) > 0
         and (firm_dom is null or (host <> firm_dom and host not like '%.' || firm_dom)) then
        lvl := 2; outcome := 'published'; reason := null;
      else
        lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: deal source is not a company press release, Form D, or a known outlet';
      end if;
    end if;
    return next; return;
  end if;

  if p_section = 'social' then
    if firm_dom is not null and (host = firm_dom or host like '%.' || firm_dom) then
      lvl := 2; outcome := 'published'; reason := null;
    else
      lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: social count is not from an account linked on the firm site';
    end if;
    return next; return;
  end if;

  if p_section in ('portfolio', 'sectors') then
    if coalesce(p_f->>'domain', '') <> '' and public._host_is(p_url, p_f->>'domain') then
      lvl := 2; outcome := 'published'; reason := null;
    else
      company_key := lower(regexp_replace(coalesce(p_f->>'company', ''), '[^a-zA-Z0-9]', '', 'g'));
      if length(company_key) >= 3 and position(company_key in lower(regexp_replace(coalesce(host, ''), '[^a-zA-Z0-9]', '', 'g'))) > 0 then
        lvl := 2; outcome := 'published'; reason := null;
      else
        lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: portfolio source is not the company''s own site';
      end if;
    end if;
    return next; return;
  end if;

  if base in (1, 2) then
    lvl := base; outcome := 'published'; reason := null;
  elsif base is null then
    lvl := null; outcome := 'failure'; reason := 'link is not real (missing, not http, or a search/chat page)';
  else
    lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: elsewhere online, not shown';
  end if;
  return next;
end $$;

revoke all on function public._checker_decide(uuid, text, jsonb, text, int, jsonb) from public, anon, authenticated;
