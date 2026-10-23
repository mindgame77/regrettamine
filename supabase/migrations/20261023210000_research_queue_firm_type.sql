-- Firm type tagging for research_queue (from SEC Form ADV Schedule D 7.B flags)
alter table public.research_queue
  add column if not exists firm_type text,
  add column if not exists fund_types text[],
  add column if not exists type_source text;
alter table public.research_queue drop constraint if exists research_queue_firm_type_chk;
alter table public.research_queue add constraint research_queue_firm_type_chk
  check (firm_type is null or firm_type in ('vc','pe','hedge','fund_of_funds','real_estate','credit','other','unknown'));
create index if not exists research_queue_firm_type_idx on public.research_queue (firm_type);
