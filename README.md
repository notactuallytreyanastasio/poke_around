# PokeAround

A StumbleUpon-style link discovery engine powered by the Bluesky firehose. Surfaces quality links from the social web, filters out noise, and uses on-device ML to categorize content for browsing.

**[Live Docs](https://notactuallytreyanastasio.github.io/poke_around/)** | **[Decision Graph](https://notactuallytreyanastasio.github.io/poke_around/graph.html)**

## Features

- **Real-time link extraction** from Bluesky's global firehose (~31 msg/sec)
- **Quality filtering** based on author credibility, account age, and spam detection
- **On-device ML tagging** with Axon/EXLA (1,700 predictions/sec on Apple Silicon)
- **ATProto integration** for decentralized storage and user bookmarks
- **Retro Mac OS UI** for browsing discovered links
- **Language filtering** for English, Spanish, Portuguese, and more

## Architecture

```
Bluesky Network
       │
       ▼
┌─────────────────┐
│   Turbostream   │  WebSocket, hydrated events
│   (Firehose)    │  ~31 msg/sec
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│    Extractor    │  Quality filtering + scoring
│                 │  ~3% pass rate
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   PostgreSQL    │  Links, tags, sessions
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
┌───────┐ ┌─────────┐
│ Axon  │ │   PDS   │
│Tagger │ │  Sync   │
└───────┘ └─────────┘
```

## Quick Start

```bash
# Install dependencies
mix setup

# Start the server
mix phx.server

# Visit http://localhost:4000/stumble
```

## Quality Filtering

Links pass through strict quality filters to surface only the best content:

| Filter | Threshold | Rationale |
|--------|-----------|-----------|
| Followers | >= 500 | Established accounts |
| Following | <= 5000 | Not follow-for-follow bots |
| Account Age | >= 1 year | Not new spam accounts |
| Post Length | >= 50 chars | Real commentary |
| Hashtags | <= 1 | Spam posts have many |
| Emojis | <= 1 | Quality posts aren't emoji-heavy |
| Has Bio | Required | Real people have bios |
| Single Link | Required | Multi-link = spam |

**Result:** ~3% of links pass these filters.

## Scoring Algorithm

Links are scored 0-100 based on author credibility:

```
score = log10(followers) × 15 + min(follower_ratio × 5, 20)
```

| Followers | Following | Score |
|-----------|-----------|-------|
| 1,000 | 200 | 65 |
| 10,000 | 500 | 80 |
| 100,000 | 100 | 95 |

## ML Tagging

Two tagging engines are available:

### Axon Tagger (Default)

On-device ML using Axon/Nx/EXLA. Fast and private.

```bash
# Train a model
mix poke.train --epochs 100 --min-tags 20

# Run tagging
mix poke.tag_axon --batch 50 --threshold 0.25
```

**Performance:**
- 286K parameters (1.14 MB model)
- 0.59ms per prediction
- 1,700 predictions/sec on Apple M Max
- 70-95% accuracy on common categories

### Ollama Tagger (Fallback)

Local LLM for niche topics and high accuracy needs.

```bash
# Requires Ollama running
ollama serve

# Run tagging
mix poke.tag --model llama3.2:3b --batch 10
```

**When to use which:**
- **Axon**: High volume, common categories, real-time
- **Ollama**: Niche topics, new categories, highest accuracy

## ATProto Integration

PokeAround integrates with the AT Protocol for decentralized storage:

- **OAuth 2.0** with PAR, PKCE, and DPoP
- **PDS Sync** publishes high-quality links to your Personal Data Server
- **Custom Lexicons** for `space.pokearound.link` and `space.pokearound.bookmark`

```elixir
# config/runtime.exs
config :poke_around, PokeAround.ATProto,
  sync_enabled: true,
  sync_min_score: 50
```

## Project Structure

```
lib/poke_around/
├── bluesky/
│   ├── firehose.ex      # WebSocket client
│   ├── parser.ex        # Event parsing
│   └── supervisor.ex    # Process supervision
├── links/
│   ├── extractor.ex     # Quality filtering
│   └── link.ex          # Ecto schema
├── ai/
│   ├── axon/
│   │   └── text_classifier.ex  # ML model
│   ├── axon_tagger.ex   # Production GenServer
│   ├── ollama.ex        # LLM client
│   └── tagger.ex        # Ollama tagger
├── atproto/
│   ├── client.ex        # PDS operations
│   ├── oauth.ex         # OAuth flow
│   ├── dpop.ex          # DPoP JWT signing
│   └── sync.ex          # Background sync
├── tags/
│   ├── tag.ex           # Tag schema
│   └── link_tag.ex      # Join table
├── links.ex             # Links context
└── tags.ex              # Tags context

lib/poke_around_web/
└── live/
    └── stumble_live.ex  # Retro Mac UI
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection | Required |
| `SECRET_KEY_BASE` | Phoenix secret | Required |
| `PHX_HOST` | Production hostname | `localhost` |
| `ATPROTO_CLIENT_ID` | OAuth client_id URL | Optional |
| `ATPROTO_SYNC_ENABLED` | Enable PDS sync | `false` |

### Application Config

```elixir
# config/config.exs

# Axon Tagger (default)
config :poke_around, PokeAround.AI.AxonTagger,
  enabled: true,
  model_path: "priv/models/tagger",
  threshold: 0.25,
  batch_size: 20,
  interval_ms: 10_000,
  langs: ["en"]

# Ollama Tagger (fallback)
config :poke_around, PokeAround.AI.Tagger,
  enabled: false,
  model: "llama3.2:3b",
  batch_size: 10,
  interval_ms: 5_000
```

## Mix Tasks

```bash
# Training
mix poke.train                    # Train Axon model
mix poke.train --epochs 100       # More epochs
mix poke.train --min-tags 20      # Only common tags
mix poke.train --test             # Run test predictions

# Tagging
mix poke.tag_axon                 # Axon tagger (fast)
mix poke.tag_axon --once          # Single batch
mix poke.tag_axon --threshold 0.3 # Higher confidence

mix poke.tag                      # Ollama tagger
mix poke.tag --model qwen3:8b     # Different model
mix poke.tag --all-langs          # All languages
```

## Requirements

- Elixir 1.15+
- PostgreSQL 14+
- (Optional) Ollama for LLM tagging

## Development

```bash
# Setup
mix setup
mix ecto.create
mix ecto.migrate

# Run tests
mix test

# Start server
mix phx.server
```

## Documentation

Full documentation is available at the [GitHub Pages site](https://notactuallytreyanastasio.github.io/poke_around/):

- **[Architecture](https://notactuallytreyanastasio.github.io/poke_around/architecture.html)** - System design and data flow
- **[Axon Tagger](https://notactuallytreyanastasio.github.io/poke_around/axon-tagger.html)** - ML model details
- **[ATProto Integration](https://notactuallytreyanastasio.github.io/poke_around/atproto-integration.html)** - OAuth and PDS sync
- **[Decision Graph](https://notactuallytreyanastasio.github.io/poke_around/graph.html)** - Architectural decisions

## Stats

Pipeline performance from a 10-minute sample:

| Stage | Count | Rate |
|-------|-------|------|
| Firehose messages | 18,800 | 31/sec |
| Posts processed | 17,385 | 29/sec |
| Links found | 4,133 | 6.9/sec |
| Links qualified | 136 | 3.3% pass |
| Axon predictions | - | 1,700/sec |

**Top tags:** weather, forecast, politics, climate, tech, news, football, music

## Future Work

- [ ] Feed Generator for Bluesky integration
- [ ] RSS feeds with topic filtering
- [ ] Engagement-based re-scoring (likes, reposts, replies)
- [ ] User bookmark syncing to personal PDS
- [ ] Ad detection via LLM analysis

## License

MIT
