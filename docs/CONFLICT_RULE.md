> Dated record, not the rulebook. The only rules are in [docs/PAGE_DATA_GUIDE.md](PAGE_DATA_GUIDE.md). Where this file disagrees with that guide, the guide wins.

# Conflict rule

Approved by Alex on 2026-10-27 at about 12:12 AM PT. This applies to every bot and every data kind.

When two sourced values disagree about the same fact:

1. **Official source wins.** A government filing (SEC, Form D, a court record, a regulator) beats the firm's own website, which beats news, which beats anything else.
2. **If the sources are equally trusted, the newer dated source wins.**
3. **Values about different things are not a conflict.** One fund's size and a total raised are both kept, each clearly labeled.
4. **If it is still undecided,** the page shows the official value with its source, and the case goes on a short weekly list for Alex.

Nothing is deleted. The losing value is kept as history with its source so it can be restored.

This document is the rule. It does not, by itself, change the database or the checker.

## Press check mark

Approved by Alex on 2026-10-27. This is separate from the conflict rule above. It applies only to press links (`press_item_firms`) and the press readers.

A press link has one of three marks:

| Mark | On the firm page |
| --- | --- |
| `checked_correct` | Shown |
| `checked_wrong` | Hidden, kept as history |
| `not_checked` | Hidden |

Press has no verified yes/no column. The page shows an article today when `press_items.data_status` is `real`, `press_item_firms.hidden` is false, and the url is not empty. Those two columns stay as a backup. Readers of press use the mark.

A link is `checked_correct` only when that show rule is already true and `press_item_firms.last_checked_at` is set. That timestamp is the evidence the link was checked. `checked_source` is not evidence: it is empty on every current link, and the pilot copy uses it as a tag, not a check.

Measured on 2026-10-27, before any apply: 293 links, all `real`, none hidden, every `last_checked_at` null. 114 of those links are on the 135 pilot firms. The proposed backfill is therefore `not_checked` for all 293, and `checked_correct` and `checked_wrong` are both 0. Applying the migration would show no press until a link is marked `checked_correct`.

`checked_wrong` is not filled from old rows, because a missing check is not a rejection. Hiding a `checked_correct` link later stores `checked_wrong`. Restoring that link stores `checked_correct` again. A new publish stores `not_checked`.

62 `press_items` have no firm link. They are not on a page and have no mark.
