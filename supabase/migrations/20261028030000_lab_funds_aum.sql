-- Sequoia only (a lab firm). Keep the $82.2B SEC figure on firms.aum_display.
-- Hide duplicate raw AUM lines and the long bot note, after a backup copy. Nothing is deleted.
-- Fill raised amounts on the two named funds that already exist.

insert into public.cleanup_backup(batch, firm_id, table_name, row_id, row_data)
select 'lab-funds-aum', f.id, 'firms', f.id,
       jsonb_build_object('aum_display', f.aum_display, 'aum_billions', f.aum_billions, 'aum_source', f.aum_source, 'aum_as_of', f.aum_as_of)
from public.firms f
where f.slug = 'sequoia'
  and not exists (
    select 1 from public.cleanup_backup b
    where b.batch = 'lab-funds-aum' and b.table_name = 'firms' and b.row_id = f.id
  );

update public.firms
   set aum_display = '$82.2B', aum_billions = 82.2
 where slug = 'sequoia' and aum_source ilike '%sec%';

insert into public.cleanup_backup(batch, firm_id, table_name, row_id, row_data)
select 'lab-funds-hide', p.firm_id, 'firm_profile_facts', p.id, to_jsonb(p)
from public.firm_profile_facts p
join public.firms f on f.id = p.firm_id
where f.slug = 'sequoia' and p.section = 'funds' and not p.hidden
  and (p.value like 'Item 5F%' or (p.label = 'Regulatory AUM' and p.value like '$82,165,771,068%'))
  and not exists (
    select 1 from public.cleanup_backup b
    where b.batch = 'lab-funds-hide' and b.row_id = p.id
  );

update public.firm_profile_facts p
   set hidden = true, hidden_reason = 'duplicate AUM or raw bot note, kept', hidden_at = now(), hidden_by = 'lab-funds'
  from public.firms f
 where f.id = p.firm_id and f.slug = 'sequoia' and p.section = 'funds' and not p.hidden
   and (p.value like 'Item 5F%' or (p.label = 'Regulatory AUM' and p.value like '$82,165,771,068%'));

insert into public.cleanup_backup(batch, firm_id, table_name, row_id, row_data)
select 'lab-funds-amount', u.firm_id, 'funds', u.id, to_jsonb(u)
from public.funds u
join public.firms f on f.id = u.firm_id
where f.slug = 'sequoia' and u.name in ('Sequoia Capital Fund, L.P.', 'Sequoia Capital Fund Feeder, L.P.')
  and not exists (select 1 from public.cleanup_backup b where b.batch = 'lab-funds-amount' and b.row_id = u.id);

update public.funds u
   set raised_usd = 22700000000, closed_on = date '2026-02-05', date_precision = 'day',
       filing_url = coalesce(nullif(u.filing_url, ''), 'https://www.sec.gov/Archives/edgar/data/1906948/000206235726000016/0002062357-26-000016-index.htm')
  from public.firms f
 where f.id = u.firm_id and f.slug = 'sequoia' and u.name = 'Sequoia Capital Fund, L.P.' and u.raised_usd is null;

update public.funds u
   set raised_usd = 7000000000, closed_on = date '2026-02-05', date_precision = 'day',
       filing_url = coalesce(nullif(u.filing_url, ''), 'https://www.sec.gov/Archives/edgar/data/1906966/000206235726000018/0002062357-26-000018-index.htm')
  from public.firms f
 where f.id = u.firm_id and f.slug = 'sequoia' and u.name = 'Sequoia Capital Fund Feeder, L.P.' and u.raised_usd is null;
