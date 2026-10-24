# Duplicate firm pages

* `merge_firms(p_keep, p_drop, p_reason)` (service role, slugs): keeps `p_keep`, soft-deletes `p_drop` (deleted_at,
  unpublished, not indexable), records `firm_slug_redirects(old_slug → new_slug)` (re-pointing older redirects), adds the
  dropped page's names as `firm_aliases` (source `merged`) so search still finds them, sets the dropped `research_queue`
  entry `duplicate_of = keep` (new research lands on the survivor), and moves saved-firm (watchlist) rows.
  Raw research submissions are untouched.
* `firm_redirect(slug)` (anon): used by the /vc/ edge when a slug has no page. Follows redirect rows (max 5 hops) to a
  live page; otherwise matches the slug as a name (`sequoia-capital` → name/display/short name/alias key) and returns a
  slug only for an unambiguous match. The edge answers **301** to `/vc/<slug>/` (or `/full/`), else 404.
* `firm_duplicate_candidates` (service role): pages that look like the same firm, for review.
* Survivor choice: launch page, then indexable, then most scans, then watchers/jobs, then having a CRD.
* Oct 24, 2026 merge: `supabase/migrations/20261024280100_merge_duplicates_data.sql` (62 pages into 48 survivors).
  Backup before applying: `/workspace/backups/pre-dedupe-2026-10-24/` on the ops box.
