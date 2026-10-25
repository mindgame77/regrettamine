-- Service-role lookup so the Stripe webhook and claim-checkout can link a paid email to an existing account.
-- Does not create a user and is not callable by visitors.

create or replace function public.user_id_for_email(p_email text)
returns uuid
language sql
stable
security definer
set search_path = auth, public
as $$
  select id from auth.users where lower(email) = lower(btrim(p_email)) limit 1;
$$;

revoke all on function public.user_id_for_email(text) from public, anon, authenticated;
grant execute on function public.user_id_for_email(text) to service_role;
