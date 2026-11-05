-- Firm header: hq_country (ISO alpha-2) so the page can put the flag after the HQ city.
-- Videos: up to 3 current YouTube rows from v2_interviews, most views first. No rows: no section.
-- The v2 schema is not created by repo migrations; on a database without v2_firm_page (CI) this is a no-op.
do $m$
declare
  d text;
  n text;
  old_hq text := $old$'short_name',f.short_name,'hq',hq,'website',f.website_url$old$;
  new_hq text := $new$'short_name',f.short_name,'hq',hq,'hq_country',case when upper(btrim(f.hq_country)) ~ '^[A-Z]{2}$' then upper(btrim(f.hq_country)) end,'website',f.website_url$new$;
  old_people text := $old$  if jsonb_array_length(it)>0 then secs := secs || jsonb_build_object('key','people','title','Team','subtitle','','renderer','people','count',jsonb_array_length(it),'unit',case when jsonb_array_length(it)=1 then 'person' else 'people' end,'teaser',it->0->>'head','items',it); end if;
  -- G5/G6 What founders say:$old$;
  new_people text := $new$  if jsonb_array_length(it)>0 then secs := secs || jsonb_build_object('key','people','title','Team','subtitle','','renderer','people','count',jsonb_array_length(it),'unit',case when jsonb_array_length(it)=1 then 'person' else 'people' end,'teaser',it->0->>'head','items',it); end if;
  -- Videos: up to 3 current YouTube interviews for this firm, most views first. None = no section.
  select coalesce(jsonb_agg(q.p order by q.rk),'[]') into it from (
    select row_number() over (order by v.view_count desc nulls last, v.interview_date desc nulls last, v.row_id) rk,
      jsonb_build_object('title',nullif(btrim(v.title),''),'channel',nullif(btrim(v.channel),''),'url',v.interview_url,
        'date',v.interview_date::text,'views',v.view_count) p
      from v2_interviews v
     where v.firm_id=fid and v.is_current and not v.archived and not v.nothing_found and not v.link_dead
       and nullif(btrim(v.title),'') is not null
       and lower(coalesce(v.interview_format,'video')) = 'video'
       and (v.interview_url ~* '^https?://((www|m|music)\.)?(youtube\.com|youtube-nocookie\.com)/' or v.interview_url ~* '^https?://youtu\.be/')
     order by v.view_count desc nulls last, v.interview_date desc nulls last, v.row_id
     limit 3
  ) q;
  if jsonb_array_length(it)>0 then secs := secs || jsonb_build_object('key','videos','count',jsonb_array_length(it),'items',it); end if;
  -- G5/G6 What founders say:$new$;
begin
  if to_regprocedure('public.v2_firm_page(text)') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;
  if to_regclass('public.v2_interviews') is null or to_regclass('public.v2_firms') is null then
    raise exception 'v2_firm_page exists but v2_interviews or v2_firms is missing';
  end if;
  select pg_get_functiondef('public.v2_firm_page(text)'::regprocedure) into d;
  if position('-- Videos: up to 3 current YouTube interviews' in d) > 0
     and position('''hq_country'',case when upper(btrim(f.hq_country))' in d) > 0 then
    raise notice 'v2_firm_page videos and hq_country already patched';
    return;
  end if;
  if position(old_hq in d) = 0 then
    raise exception 'v2_firm_page: hq anchor not found';
  end if;
  if position(old_people in d) = 0 then
    raise exception 'v2_firm_page: people block not found';
  end if;
  n := replace(d, old_hq, new_hq);
  n := replace(n, old_people, new_people);
  if position('-- Videos: up to 3 current YouTube interviews' in n) = 0
     or position('''hq_country'',case when upper(btrim(f.hq_country))' in n) = 0 then
    raise exception 'v2_firm_page: patch did not apply';
  end if;
  execute n;
end
$m$;
