# PokeAround

**Remember StumbleUpon?** That magical feeling of clicking a button and discovering something genuinely interesting on the internet? Before algorithms decided what you should see, before engagement metrics optimized for outrage, there was serendipity.

PokeAround brings that back, powered by the open social web.

**[Live Docs](https://notactuallytreyanastasio.github.io/poke_around/)** | **[Decision Graph](https://notactuallytreyanastasio.github.io/poke_around/graph.html)**

## What It Does

PokeAround connects to Bluesky's firehose—a real-time stream of every post on the network—and extracts the links people are sharing. But not just any links. It applies aggressive quality filters to surface content from credible authors: established accounts with real followings, thoughtful commentary, and no spam signals.

The result? A curated stream of interesting links you'd never find through algorithmic feeds, organized by topic through on-device ML classification.

```
31 posts/second → Quality Filter (3% pass) → ML Tagging → Browse by Topic
```

## The Philosophy

Most link aggregators optimize for engagement. PokeAround optimizes for **author credibility**:

- **500+ followers** — You've built an audience
- **Account age 1+ year** — You're not a spam account created yesterday
- **Has a bio** — Real people describe themselves
- **Thoughtful posts** — 50+ characters of actual commentary, not just a link dump
- **No spam signals** — Limited hashtags, limited emojis, single links only

This aggressive filtering means **97% of links get rejected**. What remains is genuinely interesting content from people who've earned trust through their presence on the network.

## How It Works

### 1. Firehose Connection

We connect to [Graze Turbostream](https://graze.social), a hydrated Bluesky firehose that includes author metadata (followers, bios, account age) with each post. This saves us from making thousands of API calls per second.

```
~31 messages/second → ~4,000 links/hour → ~130 qualified links/hour
```

### 2. Quality Scoring

Every link gets a score based on the author's credibility:

```elixir
score = log10(followers) × 15 + min(follower_ratio × 5, 20)
```

| Author Profile | Score | Why |
|----------------|-------|-----|
| 1K followers, 200 following | 65 | Good ratio, established |
| 10K followers, 500 following | 80 | Large audience, curated taste |
| 100K followers, 100 following | 95 | Influential, highly selective |

High follower-to-following ratio indicates someone with curated taste, not follow-for-follow behavior.

### 3. ML Classification

Links are automatically categorized using a lightweight Axon model trained on existing tagged content:

- **286K parameters** (1.14 MB model file)
- **0.59ms per prediction** on Apple Silicon
- **1,700 predictions/second** throughput
- **70-95% accuracy** on common categories

No cloud APIs. No data leaving your machine. Just fast, private, on-device inference.

### 4. Browse & Discover

A retro Mac OS-styled interface lets you browse by topic or shuffle through random discoveries:

- **Bag of Links** — 50 random quality links
- **Tag Browsing** — Filter by topic (politics, tech, music, weather, etc.)
- **Language Filter** — English, Spanish, Portuguese, and more

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Bluesky Network                         │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                    Turbostream WebSocket (~31 msg/sec)
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  Firehose                                                       │
│  • Receives hydrated posts with author metadata                 │
│  • Broadcasts to PubSub for parallel processing                 │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  Extractor                                                      │
│  • Quality filtering (followers, age, bio, spam signals)        │
│  • Credibility scoring (log-scale + ratio bonus)                │
│  • ~3% pass rate                                                │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  PostgreSQL                                                     │
│  • Links with author metadata                                   │
│  • Tags and associations                                        │
│  • Language data                                                │
└───────────────────────────────┬─────────────────────────────────┘
                                │
              ┌─────────────────┼─────────────────┐
              │                 │                 │
              ▼                 ▼                 ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│  Axon Tagger    │  │  PDS Sync       │  │  Stumble UI     │
│  On-device ML   │  │  ATProto        │  │  LiveView       │
│  1,700 pred/sec │  │  OAuth + DPoP   │  │  Retro Mac OS   │
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

## Quick Start

```bash
# Clone and setup
git clone https://github.com/notactuallytreyanastasio/poke_around
cd poke_around
mix setup

# Start the server
mix phx.server

# Visit http://localhost:4000/stumble
```

The firehose connects automatically. Links start flowing within seconds.

## Training Your Own Model

The ML tagger learns from your existing tagged links:

```bash
# Train on links with at least 20 examples per tag
mix poke.train --epochs 100 --min-tags 20

# Test predictions on sample data
mix poke.train --test

# Run the tagger on untagged links
mix poke.tag_axon --batch 50 --threshold 0.25
```

More training data = better predictions. The model improves as you accumulate tagged links.

## ATProto Integration

PokeAround speaks AT Protocol natively:

- **OAuth 2.0** with PAR, PKCE, and DPoP (the full modern security stack)
- **PDS Sync** automatically publishes high-quality links to your Personal Data Server
- **Custom Lexicons** for `space.pokearound.link` and `space.pokearound.bookmark`

Your discoveries become part of the decentralized web, stored on infrastructure you control.

```elixir
# Enable PDS sync for links scoring 50+
config :poke_around, PokeAround.ATProto,
  sync_enabled: true,
  sync_min_score: 50
```

## Performance

Real numbers from a 10-minute production sample:

| Metric | Value |
|--------|-------|
| Firehose throughput | 31 messages/sec |
| Posts with links | 4,133 (22%) |
| Links passing quality filter | 136 (3.3%) |
| Axon inference speed | 1,700 predictions/sec |
| End-to-end latency | < 100ms |

**Top discovered tags:** weather, politics, tech, news, music, football, climate, forecast

## Project Structure

```
lib/poke_around/
├── bluesky/
│   ├── firehose.ex          # WebSocket client, auto-reconnect
│   ├── parser.ex            # Turbostream event parsing
│   └── supervisor.ex        # Process supervision
├── links/
│   ├── extractor.ex         # Quality filtering + scoring
│   └── link.ex              # Ecto schema
├── ai/
│   ├── axon/
│   │   └── text_classifier.ex   # Model architecture + training
│   ├── axon_tagger.ex       # Production GenServer
│   └── supervisor.ex        # AI process supervisor
├── atproto/
│   ├── client.ex            # PDS CRUD operations
│   ├── oauth.ex             # Full OAuth 2.0 flow
│   ├── dpop.ex              # DPoP JWT signing
│   └── sync.ex              # Background sync worker
└── tags.ex                  # Tag management context

lib/poke_around_web/live/
└── stumble_live.ex          # Retro Mac OS interface
```

## Configuration

### Environment Variables

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL connection string |
| `SECRET_KEY_BASE` | Phoenix secret (generate with `mix phx.gen.secret`) |
| `PHX_HOST` | Production hostname |
| `ATPROTO_CLIENT_ID` | OAuth client_id URL (optional) |
| `ATPROTO_SYNC_ENABLED` | Enable PDS sync (default: false) |

### Application Config

```elixir
# config/config.exs

config :poke_around, PokeAround.AI.AxonTagger,
  enabled: true,
  model_path: "priv/models/tagger",
  threshold: 0.25,        # Confidence threshold for predictions
  batch_size: 20,         # Links per tagging batch
  interval_ms: 10_000,    # Tagging interval
  langs: ["en"]           # Languages to tag
```

## Requirements

- **Elixir 1.15+** with OTP 26
- **PostgreSQL 14+**
- **~50MB disk** for model and dependencies

No external APIs required. Everything runs locally.

## Development

```bash
mix setup              # Install deps, create DB, run migrations
mix test               # Run test suite (83 tests)
mix phx.server         # Start development server

# Useful during development
mix poke.train --test  # Quick model evaluation
mix poke.tag_axon --once  # Tag one batch manually
```

## Future Work

- [ ] **Feed Generator** — Publish as a Bluesky custom feed
- [ ] **RSS Export** — Subscribe to topics via RSS
- [ ] **Engagement Re-scoring** — Factor in likes/reposts over time
- [ ] **Bookmark Sync** — Save links to your personal PDS
- [ ] **Ad Detection** — Filter promotional content

## Documentation

- **[Architecture](https://notactuallytreyanastasio.github.io/poke_around/architecture.html)** — System design and data flow
- **[Axon Tagger](https://notactuallytreyanastasio.github.io/poke_around/axon-tagger.html)** — ML model details and training
- **[ATProto Integration](https://notactuallytreyanastasio.github.io/poke_around/atproto-integration.html)** — OAuth and PDS sync
- **[Decision Graph](https://notactuallytreyanastasio.github.io/poke_around/graph.html)** — Architectural decisions visualized

## Why "PokeAround"?

Because that's what you do with it. You poke around the internet, discovering things serendipitously, like we used to before algorithms took over.

## License

MIT
