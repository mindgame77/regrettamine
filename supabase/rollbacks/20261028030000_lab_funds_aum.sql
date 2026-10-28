-- Rollback for 20261028030000_lab_funds_aum.sql.
-- Puts Sequoia's backed-up AUM display, fund amounts, and hidden flags back. Does not delete rows.

update public.firms f
   set aum_display = b.row_data->>'aum_display',
       aum_billions = nullif(b.row_data->>'aum_billions', '')::numeric,
       aum_source = b.row_data->>'aum_source',
       aum_as_of = b.row_data->>'aum_as_of'
  from public.cleanup_backup b
 where b.batch = 'lab-funds-aum' and b.table_name = 'firms' and b.row_id = f.id and f.slug = 'sequoia';

update public.firm_profile_facts p
   set hidden = coalesce((b.row_data->>'hidden')::boolean, false),
       hidden_reason = b.row_data->>'hidden_reason',
       hidden_at = nullif(b.row_data->>'hidden_at', '')::timestamptz,
       hidden_by = b.row_data->>'hidden_by'
  from public.cleanup_backup b
 where b.batch = 'lab-funds-hide' and b.table_name = 'firm_profile_facts' and b.row_id = p.id;

update public.funds u
   set raised_usd = nullif(b.row_data->>'raised_usd', '')::numeric,
       closed_on = nullif(b.row_data->>'closed_on', '')::date,
       date_precision = b.row_data->>'date_precision',
       filing_url = b.row_data->>'filing_url'
  from public.cleanup_backup b
 where b.batch = 'lab-funds-amount' and b.table_name = 'funds' and b.row_id = u.id;
