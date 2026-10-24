-- On-demand emails link only to live firm pages: published, real, not test, not deleted (else no email is sent).
create or replace function public.ondemand_outbox(p_limit int default 50)
returns table(id bigint, kind text, email text, name text, slug text)
language sql stable security definer set search_path = public as $$
  select r.id, case when r.status = 'done' then 'ready' else 'refund' end, r.email, coalesce(f.display_name, f.name), f.slug
  from research_requests r join firms f on f.id = r.firm_id
  where r.status in ('done', 'refunded') and r.email is not null and r.notified_at is null and r.notify_error is null
    and f.published and f.deleted_at is null and f.data_status = 'real' and not coalesce(f.is_test, false)
  order by r.id limit greatest(1, least(coalesce(p_limit, 50), 200))
$$;
revoke all on function public.ondemand_outbox(int) from public, anon, authenticated;
