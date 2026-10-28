-- New deal path for the 10 lab firms only. A timeline line that names a company, an amount,
-- and a round is also stored as an investment. Other firms are unchanged. Nothing is deleted.

create or replace function public._deal_from_text(p_body text)
returns table(company text, round_name text, amount numeric)
language plpgsql immutable as $$
declare m text[];
begin
  m := regexp_match(coalesce(p_body, ''), 'led (.+?)''s \$([0-9]+(?:\.[0-9]+)?)([BMK]) (Series [A-Z][0-9]?|funding round)', 'i');
  if m is null then
    m := regexp_match(coalesce(p_body, ''), '^(.+?) raised an? \$([0-9]+(?:\.[0-9]+)?)([BMK]) (Series [A-Z][0-9]?) from Sequoia', 'i');
  end if;
  if m is null then return; end if;
  company := btrim(m[1]);
  round_name := case when m[4] ~* '^funding' then 'funding round' else initcap(m[4]) end;
  amount := m[2]::numeric * case upper(m[3]) when 'B' then 1000000000 when 'M' then 1000000 when 'K' then 1000 else 1 end;
  return next;
end $$;
revoke all on function public._deal_from_text(text) from public, anon, authenticated;

create or replace function public._lab_save_deal(p_firm uuid, p_company text, p_round text, p_amount numeric, p_on date, p_url text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare cid uuid; iid uuid;
begin
  if not public._lab_firm(p_firm) or coalesce(btrim(p_company), '') = '' then return null; end if;
  select id into cid from portfolio_companies where lower(name) = lower(p_company) order by created_at limit 1;
  if cid is null then
    insert into portfolio_companies(name, data_status) values (left(p_company, 200), 'real') returning id into cid;
  end if;
  select id into iid from investments
   where firm_id = p_firm and company_id = cid and coalesce(round_name, '') = coalesce(p_round, '')
   limit 1;
  if iid is not null then return iid; end if;
  insert into investments(firm_id, company_id, round_name, amount, currency, invested_on, date_precision, is_lead, source_urls, data_status, source_system)
  values (p_firm, cid, p_round, p_amount, 'USD', p_on, case when p_on is null then null else 'day' end, true,
          case when p_url ~* '^https?://' then array[p_url] else '{}' end, 'real', 'lab-deal')
  returning id into iid;
  return iid;
end $$;
revoke all on function public._lab_save_deal(uuid, text, text, numeric, date, text) from public, anon, authenticated;

create or replace function public._lab_timeline_deal() returns trigger
language plpgsql security definer set search_path = public as $$
declare d record;
begin
  if not public._lab_firm(new.firm_id) then return new; end if;
  select * into d from public._deal_from_text(new.body);
  if d.company is not null then
    perform public._lab_save_deal(new.firm_id, d.company, d.round_name, d.amount,
      case when new.date_label ~ '^\d{4}-\d{2}-\d{2}$' then new.date_label::date end, new.source_url);
  end if;
  return new;
end $$;
revoke all on function public._lab_timeline_deal() from public, anon, authenticated;

drop trigger if exists lab_timeline_deal on public.timeline_events;
create trigger lab_timeline_deal after insert on public.timeline_events
  for each row execute function public._lab_timeline_deal();
