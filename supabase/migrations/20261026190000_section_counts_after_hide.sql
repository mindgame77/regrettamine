-- Section counts are snapshotted AFTER a deliberate hide or restore, so a recorded hide/replace does not raise a false
-- "drop" alert on the next promote. record_removed(..., hide => true) and restore_hidden() now refresh the firm's
-- section_counts (no alert: the change is recorded in removed_items with a reason). Promote still compares against the
-- last snapshot, so a drop that did not go through record_removed (or a jump) still raises an alert.

create or replace function public._section_counts_refresh(p_firm uuid) returns void
 language sql security definer set search_path = public as $$
  insert into section_counts(firm_id, section, n, counted_at)
  select p_firm, c.section, c.n, now() from _section_counts_now(p_firm) c where p_firm is not null
  on conflict (firm_id, section) do update set n = excluded.n, counted_at = excluded.counted_at $$;
revoke execute on function public._section_counts_refresh(uuid) from public, anon, authenticated;

create or replace function public.record_removed(p_table text, p_row_id uuid, p_firm uuid, p_reason text, p_who text default 'cleanup', p_hide boolean default false)
 returns bigint language plpgsql security definer set search_path = public as $$
declare r jsonb; urls text[]; rid bigint;
begin
  if coalesce(btrim(p_reason), '') = '' then raise exception 'record_removed: a reason is required'; end if;
  if p_table = 'press_item_firms' then
    select to_jsonb(x) into r from press_item_firms x where x.press_item_id = p_row_id and x.firm_id = p_firm;
  else
    execute format('select to_jsonb(x) from %I x where x.id = $1', p_table) into r using p_row_id;
  end if;
  if r is null then raise exception 'record_removed: % row % not found (record before deleting)', p_table, p_row_id; end if;
  select array_agg(distinct s.url) into urls from fact_sources fs join sources s on s.id = fs.source_id
   where fs.fact_type = p_table and fs.fact_id = p_row_id;
  rid := _removed_add(p_firm, p_table, p_row_id, r, urls, p_reason, p_who);
  insert into locked_rows(table_name, row_id, firm_id, reason) values (p_table, p_row_id, p_firm, 'removed: ' || p_reason) on conflict do nothing;
  if p_hide then
    if p_table = 'press_item_firms' then
      update press_item_firms set hidden = true, hidden_reason = p_reason, hidden_at = now(), hidden_by = p_who
       where press_item_id = p_row_id and firm_id = p_firm;
    elsif p_table in ('firm_profile_facts', 'firm_legal_items', 'timeline_events', 'firm_people_roles') then
      execute format('update %I set hidden = true, hidden_reason = $2, hidden_at = now(), hidden_by = $3 where id = $1', p_table)
        using p_row_id, p_reason, p_who;
    else raise exception 'record_removed: % has no hidden flag', p_table;
    end if;
    perform _section_counts_refresh(p_firm);
  end if;
  return rid;
end $$;

create or replace function public.restore_hidden(p_table text, p_row_id uuid, p_firm uuid, p_who text default 'restore')
 returns boolean language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if p_table not in ('firm_profile_facts', 'firm_legal_items', 'timeline_events', 'press_item_firms', 'firm_people_roles') then
    raise exception 'restore_hidden: unsupported table %', p_table;
  end if;
  perform set_config('app.unhide', '1', true);
  if p_table = 'press_item_firms' then
    update press_item_firms set hidden = false, hidden_reason = null, hidden_at = now(), hidden_by = p_who
     where press_item_id = p_row_id and firm_id = p_firm and hidden;
  else
    execute format('update %I set hidden = false, hidden_reason = null, hidden_at = now(), hidden_by = $3 where id = $1 and firm_id = $2 and hidden', p_table)
      using p_row_id, p_firm, p_who;
  end if;
  get diagnostics n = row_count;
  perform set_config('app.unhide', '', true);
  if n > 0 then
    perform _section_counts_refresh(p_firm);
    delete from removed_items where source_table = p_table and source_row_id = p_row_id and firm_id = p_firm;
    delete from locked_rows where table_name = p_table and row_id = p_row_id and firm_id = p_firm and reason like 'removed: %';
  end if;
  return n > 0;
end $$;

revoke execute on function public.record_removed(text, uuid, uuid, text, text, boolean), public.restore_hidden(text, uuid, uuid, text)
  from public, anon, authenticated;
