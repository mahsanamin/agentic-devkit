# Sources to check each run

Two layers. The fetcher handles the firehose; you handle the editorial layer with WebSearch. Always scope to the watermark (`last_run`) and follow links to the primary source before logging.

## Layer 1: firehose (scripted, deterministic)

`scripts/fetch_feeds.py --since "<last_run>"` already pulls these, deduped and timestamped:

- **Hacker News** (Algolia API): AI stories above a points threshold. Good for what builders are actually talking about (tools, open models, launches).
- **arXiv** (cs.AI / cs.LG / cs.CL): newest submissions. Good for advancements and new terminology, but heavy and noisy; keep only papers with real signal (new SOTA, a named method, a release).

Treat both as discovery only. A Hacker News link points somewhere; log the destination, not the HN page.

## Layer 2: editorial (live WebSearch / WebFetch)

The fetcher cannot see most launches and announcements. Run a few targeted searches, scoped to recent days, across:

- **Labs and model makers**: OpenAI, Google DeepMind, Anthropic, Meta AI, Mistral, xAI, DeepSeek, Alibaba Qwen, Microsoft AI, Cohere, Hugging Face.
- **Outlets**: The Verge, TechCrunch, Ars Technica, VentureBeat, The Information, Reuters/Bloomberg tech.
- **Curation**: Hugging Face trending models, Papers with Code, well-known AI newsletters (Import AI, The Batch).

### Query patterns

- `AI news <this week> <month> <year>`
- `new AI model release <month> <year>`
- `<lab name> announcement <month> <year>` for any lab that has been active
- `new AI tool OR framework OR API launch <month> <year>` (for technology.md)
- `AI funding OR acquisition OR policy <month> <year>` (for news.md)
- For terms.md, when a new word keeps appearing, search `what is "<term>" AI` to get a clean definition.

## Source quality

Primary source beats aggregator beats random blog. A lab's own post, the paper, or the product page is the gold standard; a major outlet is fine; a content-farm rewrite is not, unless it is the only source, and then label the entry "(unconfirmed)". Do not log a claim you could not open and read.

## Framing the diff

`last_run` is a full timestamp, so even multiple runs in one day only pick up what is genuinely newer. If a window turns up nothing new after dedup, that is normal: log nothing and just bump `last_run`.
