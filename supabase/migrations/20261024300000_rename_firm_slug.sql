-- rename_firm_slug(old, new, display): give a live page a new slug (and optionally a new display name), keeping the old slug as a 301.
-- Used for pages that were named after a fund entity (e.g. 'Sigma Management 6' -> 'Sigma Partners', docs/DEDUPE.md).
-- Old display name stays searchable as a 'previous_display' alias. A soft-deleted (merged) page that still holds the new slug
-- gets its slug parked ('<slug>--merged-<id8>') so the name is free; its redirect row already points at a live page.
-- report_pages is keyed by slug without ON UPDATE CASCADE, so its row is moved across. Bot raw data is not touched.
create or replace function public.rename_firm_slug(p_old text, p_new text, p_display text default null, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare f firms; o firms; n text := lower(btrim(coalesce(p_new, ''))); rp report_pages;
begin
  select * into f from firms where slug = lower(btrim(p_old)) and deleted_at is null;
  if f.id is null then return jsonb_build_object('status', 'skipped', 'old', p_old); end if;
  if n !~ '^[a-z0-9][a-z0-9-]{1,80}$' then raise exception 'bad slug %', p_new; end if;

  if nullif(btrim(p_display), '') is not null and coalesce(f.display_name, f.name) is distinct from btrim(p_display) then
    insert into firm_aliases (firm_id, alias, source)
    select f.id, coalesce(f.display_name, f.name), 'previous_display'
    where lower(coalesce(f.display_name, f.name)) <> lower(btrim(p_display))
    on conflict do nothing;
    update firms set display_name = btrim(p_display), updated_at = now() where id = f.id;
  end if;
  if n = f.slug then return jsonb_build_object('status', 'display_only', 'slug', f.slug); end if;

  select * into o from firms where slug = n;
  if o.id is not null and o.deleted_at is null then raise exception 'slug % is used by a live page', n; end if;
  if o.id is not null then
    select * into rp from report_pages where slug = o.slug;
    if rp.slug is not null then delete from report_pages where slug = o.slug; end if;
    update firms set slug = n || '--merged-' || left(o.id::text, 8) where id = o.id;
    if rp.slug is not null then insert into report_pages (slug, html, created_at, updated_at)
      values (n || '--merged-' || left(o.id::text, 8), rp.html, rp.created_at, rp.updated_at); end if;
  end if;

  rp := null;
  select * into rp from report_pages where slug = f.slug;
  if rp.slug is not null then delete from report_pages where slug = f.slug; end if;
  update firms set slug = n, updated_at = now() where id = f.id;
  if rp.slug is not null then insert into report_pages (slug, html, created_at, updated_at) values (n, rp.html, rp.created_at, rp.updated_at); end if;

  delete from firm_slug_redirects where old_slug = n;
  update firm_slug_redirects set new_slug = n where new_slug = f.slug;
  insert into firm_slug_redirects (old_slug, new_slug, old_firm_id, old_registry_id, reason)
  values (f.slug, n, f.id, f.registry_id, coalesce(p_reason, 'renamed'))
  on conflict (old_slug) do update set new_slug = excluded.new_slug, reason = excluded.reason, merged_at = now();
  return jsonb_build_object('status', 'renamed', 'old', f.slug, 'new', n);
end $$;
revoke all on function public.rename_firm_slug(text, text, text, text) from public, anon, authenticated;
grant execute on function public.rename_firm_slug(text, text, text, text) to service_role;
