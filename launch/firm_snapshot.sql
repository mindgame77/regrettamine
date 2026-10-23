-- Read-only. Pulls one firm's check data from regrettamine. Only data_status='real' rows are returned;
-- needs_proof rows are only counted (for the "more being confirmed" note).
with f as (select * from firms where slug = :slug and deleted_at is null)
select json_build_object(
 'pulled_at', now(),
 'firm', (select row_to_json(f) from f),
 'facts', (select coalesce(json_agg(x order by x.fact_type, x.retrieved_at),'[]') from vc_source_facts x where firm_id=(select id from f) and data_status='real' and superseded_by is null),
 'fact_sources', (select coalesce(json_agg(json_build_object('fact_id',fs.fact_id,'fact_type',fs.fact_type,'label',fs.label,'url',s.url,'publisher',s.publisher,'title',s.title,'retrieved_at',s.retrieved_at)),'[]') from fact_sources fs join sources s on s.id=fs.source_id where fs.firm_id=(select id from f) and fs.data_status='real' and s.data_status='real' and not coalesce(s.junk,false)),
 'people', (select coalesce(json_agg(json_build_object('name',p.full_name,'role',fp.role,'start',fp.start_date,'end',fp.end_date,'notes',fp.notes) order by fp.sort_order),'[]') from fund_people fp join people p on p.id=fp.person_id where fp.firm_id=(select id from f) and fp.data_status='real' and p.data_status='real'),
 'context', (select coalesce(json_agg(c),'[]') from vc_context_notes c where firm_id=(select id from f) and data_status='real'),
 'aliases', (select coalesce(json_agg(json_build_object('type',alias_type,'value',value)),'[]') from vc_aliases where firm_id=(select id from f)),
 'team', (select coalesce(json_agg(json_build_object('name',person_name,'value',value,'source_url',source_url,'source_label',source_label,'retrieved_at',retrieved_at)),'[]') from vc_partner_history where firm_id=(select id from f) and data_status='real' and kind='team'),
 'needs_proof_count', (select (select count(*) from vc_source_facts where firm_id=(select id from f) and data_status='needs_proof') + (select count(*) from vc_context_notes where firm_id=(select id from f) and data_status='needs_proof'))
) as j;
