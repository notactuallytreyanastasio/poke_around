# PokeAround Architecture

PokeAround is a link curation system that extracts, filters, tags, and surfaces the best links shared on Bluesky. This document covers the complete system architecture.

## System Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              Bluesky Network                            │
│                                   │                                     │
│                           Turbostream (WebSocket)                       │
└───────────────────────────────────┼─────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼─────────────────────────────────────┐
│                              Firehose                                   │
│                     (WebSocket client, ~31 msg/sec)                     │
│                                   │                                     │
│                           Phoenix.PubSub                                │
│                          "firehose:events"                              │
└───────────────────────────────────┼─────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼─────────────────────────────────────┐
│                             Extractor                                   │
│                    (Quality filtering + scoring)                        │
│                                   │                                     │
│                          Links Context                                  │
│                         (PostgreSQL storage)                            │
└───────────────────────────────────┼─────────────────────────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
┌───────▼───────┐         ┌─────────▼─────────┐        ┌────────▼────────┐
│  Axon Tagger  │         │    PDS Sync       │        │   Stumble UI    │
│  (On-device)  │         │   (ATProto)       │        │  (LiveView)     │
└───────────────┘         └───────────────────┘        └─────────────────┘
```

## Core Components

### 1. Firehose (`lib/poke_around/bluesky/firehose.ex`)

WebSocket client that connects to Graze Turbostream for real-time Bluesky events.

**Why Turbostream?**
- Hydrated events: Author profiles, follower counts, bios included
- Pre-filtered: Only post creates, not all repo operations
- Lower bandwidth than raw Jetstream

**Stats:**
- ~31 messages/second average
- Auto-reconnects on disconnect
- Logs stats every 30 seconds

```elixir
# Get current stats
Firehose.get_stats()
# => %{messages_received: 50000, posts_received: 48000, messages_per_second: 31.2}
```

**Event Flow:**
1. Receive WebSocket frame
2. Parse JSON message
3. Filter for `app.bsky.feed.post` creates
4. Broadcast to `Phoenix.PubSub` topic `"firehose:events"`

### 2. Parser (`lib/poke_around/bluesky/parser.ex`)

Parses Turbostream events into typed structs.

**Structs:**
- `Post` - Full post with author, embeds, facets
- `Author` - Profile with followers, following, bio
- `ExternalEmbed` - Link card data (title, description, thumb)
- `FacetLink` - Inline link from post text

**Link Extraction:**
- External embeds (`app.bsky.embed.external`)
- Facet links (`app.bsky.richtext.facet#link`)
- Filters out `bsky.app`, `bsky.social`, `at://` URIs

### 3. Extractor (`lib/poke_around/links/extractor.ex`)

Quality filter that decides which links to store.

**Quality Thresholds:**

| Metric | Threshold | Rationale |
|--------|-----------|-----------|
| Followers | >= 500 | Established accounts |
| Following | <= 5000 | Not follow-for-follow bots |
| Account Age | >= 365 days | Not new spam accounts |
| Text Length | >= 50 chars | Real commentary, not just link dumps |
| Hashtags | <= 1 | Spam posts have many hashtags |
| Emojis | <= 1 | Quality posts aren't emoji-heavy |
| Has Bio | required | Real people have bios |
| Single Link | required | Multiple links = spam |

**Banned Domains:**
- `tinyurl.com`, `bit.ly`, `t.co` (URL shorteners)

**Stats:**
```elixir
Extractor.get_stats()
# => %{
#   posts_processed: 100000,
#   links_found: 8500,
#   links_qualified: 1200,
#   qualification_rate: 0.14
# }
```

### 4. Scoring Algorithm

Links are scored 0-100 based on author metrics. Higher scores = more trustworthy sources.

```elixir
def calculate_score(%{author: author}) do
  followers = author.followers_count || 0
  following = author.follows_count || 1

  # Base score from followers (log scale, diminishing returns)
  follower_score = :math.log10(max(followers, 1)) * 15

  # Bonus for good follower/following ratio
  # (curated taste, not follow-for-follow)
  ratio = followers / max(following, 1)
  ratio_bonus = min(ratio * 5, 20)

  # Combined score, capped at 100
  min(round(follower_score + ratio_bonus), 100)
end
```

**Score Examples:**
| Followers | Following | Ratio | Score |
|-----------|-----------|-------|-------|
| 1,000 | 200 | 5:1 | 45 + 20 = 65 |
| 10,000 | 500 | 20:1 | 60 + 20 = 80 |
| 500 | 400 | 1.25:1 | 40 + 6 = 46 |
| 100,000 | 100 | 1000:1 | 75 + 20 = 95 |

### 5. Link Storage (`lib/poke_around/links/`)

PostgreSQL storage for extracted links.

**Schema (`links` table):**
```
id              BIGSERIAL PRIMARY KEY
url             VARCHAR NOT NULL
url_hash        VARCHAR NOT NULL UNIQUE  -- SHA256 prefix for dedup

-- Source post
post_uri        VARCHAR
post_text       TEXT
post_created_at TIMESTAMP

-- Author (denormalized)
author_did           VARCHAR
author_handle        VARCHAR
author_display_name  VARCHAR
author_followers_count INTEGER

-- Quality
score           INTEGER DEFAULT 0

-- Metadata
title           VARCHAR
description     TEXT
image_url       VARCHAR
domain          VARCHAR

-- Categorization
tags            VARCHAR[] DEFAULT '{}'
langs           VARCHAR[] DEFAULT '{}'

-- Stats
stumble_count   INTEGER DEFAULT 0

-- Tagging
tagged_at       TIMESTAMP

-- ATProto sync
at_uri          VARCHAR
synced_at       TIMESTAMP
sync_status     VARCHAR
```

**URL Deduplication:**
- URLs are normalized (lowercase host, sorted query params)
- SHA256 hash prefix stored as `url_hash`
- Unique constraint prevents duplicates

### 6. Tagging System

#### Tags Context (`lib/poke_around/tags.ex`)

Manages normalized tags and link-tag associations.

**Schema:**
- `tags` - Normalized tag names with usage counts
- `link_tags` - Many-to-many join with source/confidence

**Features:**
- Slug generation (`web-dev` from "Web Dev")
- Usage count tracking
- Language filtering (English-only by default)

#### Axon Tagger (`lib/poke_around/ai/axon_tagger.ex`)

Background GenServer that tags untagged links using on-device ML with Axon/Nx/EXLA.

**Configuration:**
```elixir
config :poke_around, PokeAround.AI.AxonTagger,
  enabled: true,
  model_path: "priv/models/tagger",
  threshold: 0.25,
  batch_size: 20,
  interval_ms: 10_000,
  langs: ["en"]
```

**Model Architecture (`lib/poke_around/ai/axon/text_classifier.ex`):**
- Multi-label text classification
- 286K parameters (1.14 MB model file)
- Input: Bag-of-words text encoding (10K vocabulary)
- Hidden layers: 256 → 128 neurons with ReLU + dropout
- Output: Sigmoid activation for multi-label prediction

**Process:**
1. Query untagged English links (ordered by score)
2. Encode text using bag-of-words vocabulary
3. Run inference with trained Axon model
4. Apply confidence threshold (default 0.25)
5. Create tag associations for predictions above threshold

**Performance:**
- 0.59ms per prediction on Apple M Max
- ~1,700 predictions/sec
- 70-95% accuracy on common categories (weather, politics, tech, music)

**Training:**
```bash
# Train a model from existing tagged links
mix poke.train --epochs 100 --min-tags 20

# Run with test predictions
mix poke.train --test
```

**Stats:**
```elixir
AxonTagger.stats()
# => %{
#   enabled: true,
#   model_loaded: true,
#   processed: 5000,
#   untagged_count: 1200,
#   tags_available: 52
# }
```

### 7. Stumble UI (`lib/poke_around_web/live/stumble_live.ex`)

LiveView interface with retro Mac OS aesthetic.

**Features:**
- **Bag of Links**: Random 50 links (min score 20)
- **Tag Browsing**: Browse by popular tags
- **Your Links**: (Placeholder) User's saved links
- **Language Filter**: English, Spanish, Portuguese, etc.
- **Shuffle**: Get a new random set

**Stumble Flow:**
1. Load 50 random links with `min_score: 20`
2. Filter by selected languages
3. Click link to open + increment `stumble_count`

### 8. Bookmarklet API (`lib/poke_around_web/controllers/api/link_controller.ex`)

JSON API for the bookmarklet to submit links.

**Endpoint:** `POST /api/links`

```json
{
  "url": "https://example.com/article",
  "title": "Article Title",
  "description": "Optional description"
}
```

**Response:**
```json
{
  "id": 123,
  "url": "https://example.com/article",
  "score": 50
}
```

User-submitted links get a default score of 50.

## Supervisor Tree

```
PokeAround.Application
├── PokeAroundWeb.Telemetry
├── PokeAround.Repo
├── DNSCluster
├── Phoenix.PubSub
├── PokeAround.Bluesky.Supervisor
│   ├── Firehose
│   └── Extractor
├── PokeAround.AI.Supervisor
│   └── AxonTagger
├── PokeAround.ATProto.Supervisor
│   ├── TID (Agent)
│   └── Sync (GenServer)
└── PokeAroundWeb.Endpoint
```

## Data Flow

### Link Ingestion

```
Turbostream → Firehose → Parser → Extractor → Links.store_link()
                 │
                 ▼
            PubSub: "firehose:events"
```

### Tag Processing

```
AxonTagger (every 10s)
    │
    ▼
Tags.untagged_links(20, langs: ["en"])
    │
    ▼
TextClassifier.predict(model, text)
    │
    ▼
Filter predictions > threshold (0.25)
    │
    ▼
Tags.tag_link(link, predicted_tags)
```

### PDS Sync

```
Sync (every 60s)
    │
    ▼
get_links_to_sync(min_score: 50, limit: 20)
    │
    ▼
Client.create_record(session, "space.pokearound.link", record)
    │
    ▼
Update link: at_uri, synced_at, sync_status
```

## Configuration

### Environment

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection | Required |
| `SECRET_KEY_BASE` | Phoenix secret | Required |
| `PHX_HOST` | Production hostname | `localhost` |
| `ATPROTO_CLIENT_ID` | OAuth client_id URL | Required for ATProto |
| `ATPROTO_SYNC_ENABLED` | Enable PDS sync | `false` |
| `ATPROTO_SYNC_MIN_SCORE` | Sync threshold | `50` |

### Application Config

```elixir
# Firehose
config :poke_around, PokeAround.Bluesky.Firehose,
  url: "wss://api.graze.social/app/api/v1/turbostream/turbostream"

# Axon Tagger
config :poke_around, PokeAround.AI.AxonTagger,
  enabled: true,
  model_path: "priv/models/tagger",
  threshold: 0.25,
  batch_size: 20,
  interval_ms: 10_000,
  langs: ["en"]

# ATProto
config :poke_around, PokeAround.ATProto,
  sync_min_score: 50,
  sync_enabled: true
```

## Database Indexes

```sql
-- Deduplication
CREATE UNIQUE INDEX links_url_hash_index ON links(url_hash);

-- Stumble queries (random by score)
CREATE INDEX links_score_index ON links(score);

-- Language filtering (GIN for array overlap)
CREATE INDEX links_langs_index ON links USING GIN(langs);

-- Tagging queue
CREATE INDEX links_tagged_at_index ON links(tagged_at);

-- ATProto sync queue
CREATE INDEX links_sync_status_index ON links(sync_status);
CREATE INDEX links_at_uri_index ON links(at_uri);

-- Tag lookups
CREATE INDEX link_tags_link_id_index ON link_tags(link_id);
CREATE INDEX link_tags_tag_id_index ON link_tags(tag_id);
CREATE UNIQUE INDEX tags_slug_index ON tags(slug);
```

## Performance Characteristics

| Metric | Value |
|--------|-------|
| Firehose throughput | ~31 msg/sec |
| Qualification rate | ~14% of posts with links |
| Axon inference | 0.59ms per prediction (~1,700/sec) |
| Tagging batch | 20 links every 10 seconds |
| PDS sync batch | 20 links every 60 seconds |
| Stumble query | 50 random links, ~20ms |

## Future Enhancements

- [ ] Feed Generator for Bluesky integration
- [ ] RSS feeds with topic filtering
- [ ] User bookmarks synced to personal PDS
- [ ] Bookmarklet popup OAuth flow
- [ ] Metadata scraping (OpenGraph, title extraction)
- [ ] Score decay over time
- [ ] Domain reputation tracking
