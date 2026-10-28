# Bots

The only rulebook is [docs/PAGE_DATA_GUIDE.md](PAGE_DATA_GUIDE.md). Do not follow `docs/archive/`, `docs/DATA_RULES.md`, `docs/ENRICHER.md`, `docs/GOLD_EXAMPLES.md`, `docs/HOW_IT_WORKS.md`, or any other old rules file where it disagrees with the guide.

This applies to every sender:

- Researchers (`toxy-researcher-*`)
- List builders
- The Enricher (`toxy-enricher`), as a finder only. It does not publish.
- The Checker, the only publisher
- The Activity Collector. It does not write `investments` directly.
- The friend’s portal bots (`portal-night-bot*`)

All of them send into the holding area `bots.research_submissions`. The lab scope and the call shape for the night run are in [tools/ingest/external-bot-night-run.md](../tools/ingest/external-bot-night-run.md). Never print an ingest key.
