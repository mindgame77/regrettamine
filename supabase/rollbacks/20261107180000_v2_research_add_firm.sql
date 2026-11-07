-- Undo add_firm. Drops the function only. Firm rows already created stay.
drop function if exists public.v2_research_add_firm(uuid, jsonb);
