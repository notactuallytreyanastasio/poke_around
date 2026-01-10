# PokeAround

A StumbleUpon-style link discovery engine powered by the Bluesky firehose. Surfaces quality links from the social web, filters out noise, and uses AI to categorize content for browsing.

## How It Works: Firehose to Curated Content

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           THE PIPELINE                                       │
└─────────────────────────────────────────────────────────────────────────────┘

    ┌──────────────┐
    │   BLUESKY    │  ~31 messages/sec from the entire network
    │   FIREHOSE   │  All posts, likes, follows, etc.
    └──────┬───────┘
           │
           ▼
    ┌──────────────┐
    │  TURBOSTREAM │  Graze API provides "hydrated" events
    │   (WebSocket)│  Author profiles pre-fetched, not just DIDs
    └──────┬───────┘
           │
           ▼
    ┌──────────────┐
    │   FIREHOSE   │  Filters to post creates only
    │   GENSERVER  │  Broadcasts to PubSub: "firehose:events"
    └──────┬───────┘
           │
           ▼
    ┌──────────────┐  QUALITY FILTERS:
    │    LINK      │  • Follower count >= 500
    │  EXTRACTOR   │  • Following <= 5000 (not follow-for-follow)
    │              │  • Account age >= 1 year
    │              │  • Has bio (not a bot)
    │              │  • Post text >= 50 chars (after removing hashtags)
    │              │  • Max 1 hashtag (not hashtag spam)
    │              │  • Max 1 emoji (not emoji spam)
    │              │  • Single link only (multi-link = spam)
    │              │  • No banned domains (t.co, bit.ly, tinyurl)
    └──────┬───────┘
           │
           │  ~3% of links pass these filters
           ▼
    ┌──────────────┐
    │   POSTGRES   │  Stored with metadata:
    │   DATABASE   │  • URL, domain, hash (dedup)
    │              │  • Post text, author info
    │              │  • Score (log follower + ratio bonus)
    │              │  • Languages detected
    └──────┬───────┘
           │
           ▼
    ┌──────────────┐
    │    OLLAMA    │  Local LLM (llama3.2:3b) generates tags
    │    TAGGER    │  Parallel processing, 10 links/batch
    │              │  ~30 links/minute throughput
    │              │  Tags: "politics", "tech", "music", etc.
    └──────┬───────┘
           │
           ▼
    ┌──────────────┐
    │   STUMBLE    │  Retro Mac OS-style UI
    │   LIVEVIEW   │  Random links, filter by language/tag
    │              │  "Bag of Links", "Tag Browsing", "Your Links"
    └──────────────┘
```

## Pipeline Stats (10-minute sample)

| Stage | Count | Rate |
|-------|-------|------|
| Firehose messages | 18,800 | 31/sec |
| Posts processed | 17,385 | 29/sec |
| Links found | 4,133 | 6.9/sec |
| Links qualified | 136 | 3.3% pass rate |
| Unique tags created | 2,405 | - |

**Top discovered tags:** weather, forecast, politics, climate, trump, news, venezuela, football, immigration

## Quality Scoring

Links are scored 0-100 based on author credibility:

```
score = log10(followers) * 15 + min(follower_ratio * 5, 20)
```

- **Follower base:** Logarithmic scale, diminishing returns after ~10K
- **Ratio bonus:** High follower/following ratio = curated taste, not follow-for-follow
- **Capped at 100**

Example: Author with 384K followers, good ratio = score 100

## Running

### Full server (firehose + tagger + web UI)

```bash
mix phx.server
# Visit http://localhost:4000
```

### Standalone tagger (no server needed)

```bash
# Run in background while working
mix poke.tag

# Options
mix poke.tag --batch 20          # Larger batches
mix poke.tag --interval 10000    # 10s between batches
mix poke.tag --model qwen3:8b    # Different model
mix poke.tag --all-langs         # Tag all languages, not just English
mix poke.tag --once              # One batch and exit (for cron)
```

## Architecture

```
lib/poke_around/
├── bluesky/
│   ├── firehose.ex      # WebSocket client for Turbostream
│   ├── parser.ex        # Parse events into typed structs
│   ├── supervisor.ex    # Supervises firehose + extractor
│   └── types.ex         # Post, Author, Embed structs
├── links/
│   ├── extractor.ex     # Quality filtering, scoring
│   └── link.ex          # Ecto schema
├── ai/
│   ├── ollama.ex        # HTTP client for Ollama API
│   ├── tagger.ex        # Background tag processor
│   └── supervisor.ex    # AI service supervision
├── tags/
│   ├── tag.ex           # Tag schema
│   └── link_tag.ex      # Many-to-many join
├── links.ex             # Links context (queries)
└── tags.ex              # Tags context (tagging, queries)

lib/poke_around_web/
└── live/
    └── stumble_live.ex  # Main UI
```

## Requirements

- Elixir 1.15+
- PostgreSQL
- Ollama running locally (`ollama serve`)
- A model pulled (`ollama pull llama3.2:3b`)

## Setup

```bash
mix setup
mix ecto.create
mix ecto.migrate
mix phx.server
```

## Future: Engagement Enrichment (Planned)

Currently links are scored at capture time based on author metrics. Planned enhancement:

1. **Capture** links immediately (current behavior)
2. **Wait 30 minutes** for engagement to accumulate
3. **Fetch engagement** via Bluesky API (replies, likes, reposts)
4. **Re-score** based on actual response:
   - Replies weighted highest (effort to respond)
   - Reposts weighted medium (amplification signal)
   - Likes weighted lowest (low effort)
5. **Surface** only engagement-verified links in "Best" feed

Plus ad detection via LLM analysis of post language patterns.
