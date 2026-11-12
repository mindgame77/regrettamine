-- Visitor firm-search log. One small insert per finished search so research can see
-- which names people look for, including searches that match no firm.
-- Not applied to production by this file landing in the repo. Apply it by hand after review.
-- The write path is the log_search RPC only: anon has no table privileges and RLS has no policies.
-- top_firm_id is the public slug. firm_directory and firm_suggest do not return the numeric firm id.
-- Indexes are created_at (the hourly cap reads the last hour) and term_norm (the demand summary). No others.

create table public.v2_search_log (
  id bigserial primary key,
  term text not null,
  term_norm text,
  page text,
  result_count int,
  top_firm_id text,
  anon_key text,
  created_at timestamptz not null default now()
);

alter table public.v2_search_log enable row level security;
revoke all on table public.v2_search_log from public, anon, authenticated;
revoke all on sequence public.v2_search_log_id_seq from public, anon, authenticated;

create index v2_search_log_created_at_idx on public.v2_search_log (created_at);
create index v2_search_log_term_norm_idx on public.v2_search_log (term_norm);

create or replace function public.log_search(
  p_term text,
  p_page text,
  p_result_count int,
  p_top_firm_id text,
  p_anon_key text
) returns void
language plpgsql
security definer
set search_path = public
set statement_timeout = '1s'
as $$
declare
  v_term text;
  v_page text;
  v_top text;
  v_anon text;
  v_n int;
begin
  v_term := left(regexp_replace(regexp_replace(btrim(coalesce(p_term, '')), '[[:cntrl:]]', '', 'g'), '\s+', ' ', 'g'), 100);
  if char_length(v_term) < 2 then
    return;
  end if;
  v_page := nullif(left(regexp_replace(btrim(coalesce(p_page, '')), '[[:cntrl:]]', '', 'g'), 40), '');
  v_top := nullif(left(btrim(coalesce(p_top_firm_id, '')), 80), '');
  if v_top is not null and v_top !~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$' then
    v_top := null;
  end if;
  v_anon := nullif(btrim(coalesce(p_anon_key, '')), '');
  if v_anon is null or v_anon !~ '^[A-Za-z0-9_-]{8,80}$' then
    v_anon := null;
  end if;
  v_n := least(greatest(coalesce(p_result_count, 0), 0), 1000000);
  insert into public.v2_search_log (term, term_norm, page, result_count, top_firm_id, anon_key)
  select v_term, lower(v_term), v_page, v_n, v_top, v_anon
  where (
    select count(*) from public.v2_search_log
    where created_at > now() - interval '1 hour'
      and anon_key is not distinct from v_anon
  ) < 30;
end;
$$;

revoke all on function public.log_search(text, text, int, text, text) from public, anon, authenticated;
grant execute on function public.log_search(text, text, int, text, text) to anon;

comment on function public.log_search(text, text, int, text, text) is
  'One visitor firm search. Trims, caps the term at 100 characters, drops terms under 2 characters, and keeps at most 30 rows per anon key per hour.';

-- Internal summary. No anon or authenticated grant. security_invoker so a later grant still hits RLS.
create view public.search_demand
with (security_invoker = true) as
select
  term_norm,
  count(*)::bigint as searches,
  max(created_at) as last_seen,
  count(*) filter (where result_count = 0)::bigint as zero_results
from public.v2_search_log
group by term_norm;

revoke all on table public.search_demand from public, anon, authenticated;

comment on view public.search_demand is
  'Internal. How often each normalized visitor search appears, when it was last seen, and how many of those searches matched no firm.';
