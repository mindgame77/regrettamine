-- Fix 409 race: page calls check_balance and unlock_firm at once for a new anon id; both tried to insert.
create or replace function public._balance(p_anon uuid) returns public.check_balances
language plpgsql security definer set search_path = public as $$
declare b public.check_balances;
begin
  if auth.uid() is not null then
    insert into check_balances(user_id) values (auth.uid()) on conflict (user_id) do nothing;
    select * into b from check_balances where user_id = auth.uid() for update;
    if not b.signup_bonus_given then
      update check_balances set free_left = free_left + 4, signup_bonus_given = true, updated_at = now() where id = b.id returning * into b;
      insert into check_events(balance_id, kind, amount) values (b.id, 'grant_signup', 4);
    end if;
  else
    if p_anon is null then raise exception 'anon id required'; end if;
    insert into check_balances(anon_id) values (p_anon) on conflict (anon_id) do nothing;
    select * into b from check_balances where anon_id = p_anon and user_id is null for update;
  end if;
  return b;
end $$;
revoke all on function public._balance(uuid) from public, anon, authenticated;
