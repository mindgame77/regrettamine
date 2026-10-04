-- Settings: a website on the profile, billing status for the signed-in user,
-- and account deletion that removes the auth user after their rows.

alter table public.profiles
  add column if not exists website text;

comment on column public.profiles.website is
  'Public website. Stored only as an http(s) URL; a missing scheme becomes https://.';

create or replace function public.normalize_profile()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  raw text;
begin
  if new.display_name is not null then
    new.display_name := nullif(btrim(new.display_name), '');
  end if;

  if new.website is null or btrim(new.website) = '' then
    new.website := null;
    return new;
  end if;

  raw := btrim(new.website);
  if raw ~* '^[a-z][a-z0-9+.-]*:' and raw !~* '^https?://' then
    raise exception 'website must be an http(s) URL' using errcode = 'check_violation';
  end if;
  if raw !~* '^https?://' then
    raw := 'https://' || raw;
  end if;
  if raw !~* '^https?://[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+(:(0|[1-9][0-9]{0,4}))?([/?#][^[:space:]]*)?$'
     or raw ~ '@'
     or char_length(raw) > 300 then
    raise exception 'website must be an http(s) URL' using errcode = 'check_violation';
  end if;
  new.website := raw;
  return new;
end;
$$;

drop trigger if exists normalize_profile on public.profiles;
create trigger normalize_profile
  before insert or update on public.profiles
  for each row execute function public.normalize_profile();

-- Billing shape the settings page reads. Card, charges, and payment_failed
-- stay empty until a Stripe webhook fills them. Not a client write path.
create or replace function public.my_billing()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'tier', public.access_tier(),
    'plan', case when public.access_tier() = 'paid' then 'Paid' else 'Free' end,
    'price_label', null,
    'next_charge_label', null,
    'card', null,
    'payments', '[]'::jsonb,
    'payment_failed', false
  );
$$;

revoke all on function public.my_billing() from public;
grant execute on function public.my_billing() to authenticated, service_role;

-- Deletes the signed-in user's rows, then the auth user.
-- Reviews are removed first: profile_id is ON DELETE SET NULL, so dropping
-- the profile would keep the review and only clear the author.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  delete from public.review_ratings
  where review_id in (select id from public.reviews where profile_id = uid);

  delete from public.reviews where profile_id = uid;
  delete from public.watchlist where profile_id = uid;
  delete from public.fund_alert_settings where profile_id = uid;
  delete from public.alert_preferences where profile_id = uid;
  delete from public.report_views where profile_id = uid;
  delete from public.subscriptions where profile_id = uid;
  delete from public.profiles where id = uid;
  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
