-- Sequoia only. Lists the 10 timeline lines that are deals. sequoia_timeline_deals(false)
-- is the dry run. sequoia_timeline_deals(true) copies them into investments and leaves the
-- timeline rows in place. Nothing is deleted.

create or replace function public._deal_from_text(p_body text)
returns table(company text, round_name text, amount numeric)
language plpgsql immutable as $$
declare m text[];
begin
  m := regexp_match(coalesce(p_body, ''), 'led (.+?)''s? \$([0-9]+(?:\.[0-9]+)?)([BMK]) (Series [A-Z][0-9]?|funding round)', 'i');
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

create or replace function public.sequoia_timeline_deals(p_apply boolean)
returns table(timeline_id uuid, company text, round_name text, amount numeric, invested_on date)
language plpgsql security definer set search_path = public as $$
declare r record; d record; cid uuid; fid uuid;
begin
  select id into fid from firms where slug = 'sequoia';
  if fid is null then return; end if;
  for r in
    select t.id, t.body, t.date_label, t.source_url
    from timeline_events t
    where t.firm_id = fid
  loop
    select * into d from public._deal_from_text(r.body);
    if d.company is null then continue; end if;
    timeline_id := r.id; company := d.company; round_name := d.round_name; amount := d.amount;
    invested_on := case when r.date_label ~ '^\d{4}-\d{2}-\d{2}$' then r.date_label::date end;
    if p_apply then
      select id into cid from portfolio_companies where lower(name) = lower(d.company) order by created_at limit 1;
      if cid is null then
        insert into portfolio_companies(name, data_status) values (left(d.company, 200), 'real') returning id into cid;
      end if;
      if not exists (select 1 from investments i where i.firm_id = fid and i.company_id = cid and coalesce(i.round_name, '') = coalesce(d.round_name, '')) then
        insert into investments(firm_id, company_id, round_name, amount, currency, invested_on, date_precision, is_lead, source_urls, data_status, source_system)
        values (fid, cid, d.round_name, d.amount, 'USD', invested_on, case when invested_on is null then null else 'day' end, true,
                case when r.source_url ~* '^https?://' then array[r.source_url] else '{}' end, 'real', 'sequoia-timeline-deal');
      end if;
    end if;
    return next;
  end loop;
end $$;
revoke all on function public.sequoia_timeline_deals(boolean) from public, anon, authenticated;
