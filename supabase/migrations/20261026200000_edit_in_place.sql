-- In-place edit for cleanup: fix a live row's own fields where it sits, with a backup, instead of add-new + hide-old.
-- No new row, no hidden copy, no removed_items fingerprint, same sort_order (stays where it is on the page).
--  edit_in_place(table, row, firm, fields, batch, who): saves the row to cleanup_backup(batch), updates only the
--    allowed columns, then re-checks the row with _data_rule (same inputs as data_rules_report) and refuses (rolls
--    back) if it still breaks a rule, if it would duplicate or share a stable key with another live row, or if the row
--    is hidden, locked, or not on that firm. Returns the backup id.
--  undo_edit_in_place(backup id): puts the backed-up values back.

create table if not exists public.cleanup_backup (
  id bigserial primary key, batch text not null, firm_id uuid, table_name text, row_id uuid, row_data jsonb,
  enrichment_id bigint, saved_at timestamptz default now());
alter table public.cleanup_backup enable row level security;
revoke all on public.cleanup_backup from anon, authenticated;

create or replace function public._edit_cols(p_table text) returns text[] language sql immutable as $$
  select case p_table
    when 'firm_people_roles' then array['person_name', 'role', 'kind', 'badge', 'internal_note']
    when 'firm_legal_items' then array['title', 'year_label', 'role', 'state', 'status_label', 'tone', 'note', 'grp']
    when 'firm_profile_facts' then array['label', 'value', 'section', 'hero_label', 'hero_value']
    when 'timeline_events' then array['date_label', 'body']
  end $$;

-- the rule check for one live row, built exactly like data_rules_report() (rule + duplicate)
create or replace function public._row_rule(p_table text, p_row uuid) returns text
 language plpgsql stable set search_path = public as $$
declare url text; why text;
begin
  select min(s.url) filter (where s.url ~* '^https?://') into url
    from fact_sources fs join sources s on s.id = fs.source_id where fs.fact_type = p_table and fs.fact_id = p_row;
  if p_table = 'firm_profile_facts' then
    select _data_rule(x.section, case when x.label ~* '^lead' then 'lead' else 'live' end, jsonb_build_object('label', x.label, 'value', x.value), url)
      into why from firm_profile_facts x where x.id = p_row;
    if why is null and exists (select 1 from firm_profile_facts a join firm_profile_facts b on b.firm_id = a.firm_id and b.id <> a.id and not b.hidden
        and b.section || '|' || lower(b.label) || '|' || _norm_txt(b.value) = a.section || '|' || lower(a.label) || '|' || _norm_txt(a.value) where a.id = p_row) then
      why := 'duplicate: same as another row on this page'; end if;
  elsif p_table = 'firm_legal_items' then
    select _data_rule('legal', 'live', jsonb_build_object('title', x.title, 'status', x.status_label, 'allegation', coalesce(x.tone, '') ~* '(lead|allegation)'), url)
      into why from firm_legal_items x where x.id = p_row;
    if why is null and exists (select 1 from firm_legal_items a join firm_legal_items b on b.firm_id = a.firm_id and b.id <> a.id and not b.hidden
        and _norm_txt(b.title) = _norm_txt(a.title) where a.id = p_row) then why := 'duplicate: same as another row on this page'; end if;
  elsif p_table = 'timeline_events' then
    select _data_rule('timeline', 'live', jsonb_build_object('date', x.date_label, 'event', x.body), url) into why from timeline_events x where x.id = p_row;
    if why is null and exists (select 1 from timeline_events a join timeline_events b on b.firm_id = a.firm_id and b.id <> a.id and not b.hidden
        and b.date_label || '|' || _norm_txt(b.body) = a.date_label || '|' || _norm_txt(a.body) where a.id = p_row) then
      why := 'duplicate: same as another row on this page'; end if;
  elsif p_table = 'firm_people_roles' then
    select _data_rule('people', case when coalesce(x.badge, '') ~* 'lead' then 'lead' else 'live' end, jsonb_build_object('name', x.person_name, 'role', x.role), url)
      into why from firm_people_roles x where x.id = p_row;
    if why is null and exists (select 1 from firm_people_roles a join firm_people_roles b on b.firm_id = a.firm_id and b.id <> a.id and not b.hidden
        and b.kind || '|' || _norm_txt(b.person_name) || '|' || _norm_txt(b.role) = a.kind || '|' || _norm_txt(a.person_name) || '|' || _norm_txt(a.role)
        where a.id = p_row) then why := 'duplicate: same as another row on this page'; end if;
  end if;
  return why;
end $$;

create or replace function public.edit_in_place(p_table text, p_row uuid, p_firm uuid, p_fields jsonb, p_batch text, p_who text default 'cleanup')
 returns bigint language plpgsql security definer set search_path = public as $$
declare r jsonb; k text; bid bigint; why text; sk text; cols text[] := _edit_cols(p_table);
begin
  if cols is null then raise exception 'edit_in_place: unsupported table %', p_table; end if;
  if coalesce(btrim(p_batch), '') = '' then raise exception 'edit_in_place: a batch id is required'; end if;
  if p_fields is null or jsonb_typeof(p_fields) <> 'object' or p_fields = '{}' then raise exception 'edit_in_place: no fields'; end if;
  for k in select jsonb_object_keys(p_fields) loop
    if not k = any(cols) then raise exception 'edit_in_place: % is not editable on %', k, p_table; end if;
    if jsonb_typeof(p_fields->k) not in ('string', 'null') then raise exception 'edit_in_place: % must be text or null', k; end if;
  end loop;
  execute format('select to_jsonb(x) from %I x where x.id = $1 for update', p_table) into r using p_row;
  if r is null then raise exception 'edit_in_place: % row % not found', p_table, p_row; end if;
  if (r->>'firm_id')::uuid is distinct from p_firm then raise exception 'edit_in_place: row % is not on firm %', p_row, p_firm; end if;
  if (r->>'hidden')::boolean then raise exception 'edit_in_place: row % is hidden', p_row; end if;
  if _is_locked(p_table, p_row, p_firm) then raise exception 'edit_in_place: row % is locked', p_row; end if;
  insert into cleanup_backup(batch, firm_id, table_name, row_id, row_data) values (p_batch, p_firm, p_table, p_row, r) returning id into bid;
  for k in select jsonb_object_keys(p_fields) loop
    execute format('update %I set %I = $1 where id = $2', p_table, k) using p_fields->>k, p_row;
  end loop;
  why := _row_rule(p_table, p_row);
  if why is not null then raise exception 'edit_in_place: row % still breaks a rule after the edit: %', p_row, why; end if;
  execute format('select stable_key from %I where id = $1', p_table) into sk using p_row;
  if sk is not null and sk is distinct from r->>'stable_key' then
    execute format('select 1 from %I where firm_id = $1 and id <> $2 and not hidden and stable_key = $3 limit 1', p_table) into why using p_firm, p_row, sk;
    if why is not null then raise exception 'edit_in_place: row % would share stable key % with another live row', p_row, sk; end if;
  end if;
  perform _section_counts_refresh(p_firm);
  return bid;
end $$;

create or replace function public.undo_edit_in_place(p_backup bigint, p_who text default 'undo')
 returns boolean language plpgsql security definer set search_path = public as $$
declare b record; k text;
begin
  select * into b from cleanup_backup where id = p_backup;
  if b is null or _edit_cols(b.table_name) is null then raise exception 'undo_edit_in_place: backup % not found or not an in-place edit', p_backup; end if;
  foreach k in array _edit_cols(b.table_name) loop
    execute format('update %I set %I = $1 where id = $2 and firm_id = $3', b.table_name, k) using b.row_data->>k, b.row_id, b.firm_id;
  end loop;
  perform _section_counts_refresh(b.firm_id);
  return true;
end $$;

-- many edits, each in its own savepoint: one refused edit does not undo the others. items: [{table,row,firm,fields}]
create or replace function public.edit_in_place_batch(p_items jsonb, p_batch text, p_who text default 'cleanup')
 returns table(row_id uuid, backup_id bigint, error text) language plpgsql security definer set search_path = public as $$
declare it jsonb;
begin
  for it in select * from jsonb_array_elements(p_items) loop
    row_id := (it->>'row')::uuid; backup_id := null; error := null;
    begin
      backup_id := edit_in_place(it->>'table', row_id, (it->>'firm')::uuid, it->'fields', p_batch, p_who);
    exception when others then error := sqlerrm;
    end;
    return next;
  end loop;
end $$;

revoke execute on function public.edit_in_place_batch(jsonb, text, text) from public, anon, authenticated;
revoke execute on function public._edit_cols(text), public._row_rule(text, uuid), public.edit_in_place(text, uuid, uuid, jsonb, text, text),
  public.undo_edit_in_place(bigint, text) from public, anon, authenticated;
