-- Lab firms only. A lead with no source, and an allegation without a court or regulator
-- document, is rejected instead of held. A conflict is copied onto a weekly list.
-- A fix that cites sec.gov is listed and is not written over the page. Nothing is deleted.

create table if not exists public.conflict_weekly (
  id bigserial primary key,
  firm_id uuid,
  section text,
  kind text,
  item jsonb,
  reason text,
  created_at timestamptz not null default now()
);
alter table public.conflict_weekly enable row level security;
revoke all on public.conflict_weekly from public, anon, authenticated;

create or replace function public._lab_rule_on_check() returns trigger
language plpgsql security definer set search_path = public as $$
declare src text;
begin
  if not public._lab_firm(new.firm_id) then return new; end if;
  src := coalesce(new.item->>'source_url', new.item->>'source', new.item->>'url', '');
  if new.outcome = 'held' and new.kind = 'lead' and src !~* '^https?://' then
    new.outcome := 'rejected';
    new.reason := 'lead: rejected until it has a source';
  elsif new.outcome = 'held' and coalesce(new.item->>'allegation', '') in ('true', 't', '1')
        and src !~* '(courtlistener\.com|uscourts\.gov|pacer\.gov|sec\.gov|finra\.org|fca\.org\.uk)' then
    new.outcome := 'rejected';
    new.reason := 'allegation: needs a court or regulator document';
  elsif new.outcome = 'held' and new.kind = 'fix' and src ~* '(^|\.)sec\.gov/' then
    insert into public.conflict_weekly(firm_id, section, kind, item, reason)
    values (new.firm_id, new.section, new.kind, new.item, 'official SEC source kept for the weekly list; the page was not overwritten');
  elsif new.outcome = 'conflict' then
    insert into public.conflict_weekly(firm_id, section, kind, item, reason)
    values (new.firm_id, new.section, new.kind, new.item, new.reason);
  end if;
  return new;
end $$;
revoke all on function public._lab_rule_on_check() from public, anon, authenticated;

drop trigger if exists lab_rule_on_check on public.publish_checks;
create trigger lab_rule_on_check before insert on public.publish_checks
  for each row execute function public._lab_rule_on_check();
