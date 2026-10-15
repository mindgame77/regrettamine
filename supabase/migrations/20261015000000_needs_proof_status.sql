-- Third data_status value: 'needs_proof' = a real claim that still lacks a source URL + retrieved_at
-- (or an independent check). 'test' now means placeholder/mock only.
-- Kept alone in its own file: a new enum value cannot be used in the transaction that adds it, so later
-- migrations only reference it inside plpgsql bodies (resolved at call time, not at create time).
alter type public.data_status add value if not exists 'needs_proof';
