-- Allow non-VC startup investor types in research_queue + source tracking columns
alter table public.research_queue drop constraint if exists research_queue_firm_type_chk;
alter table public.research_queue add constraint research_queue_firm_type_chk
  check (firm_type is null or firm_type in ('vc','pe','hedge','fund_of_funds','real_estate','credit','other','unknown',
                                            'accelerator','incubator','angel_group','corporate_vc'));
alter table public.research_queue
  add column if not exists type_source_url text,
  add column if not exists list_source text;
