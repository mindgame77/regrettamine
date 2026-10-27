create index if not exists search_log_enrichment_idx on bots.search_log (enrichment_id) where enrichment_id is not null;
