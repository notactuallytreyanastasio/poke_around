# PokeAround

**Remember StumbleUpon?** That magical feeling of clicking a button and discovering something genuinely interesting on the internet? Before algorithms decided what you should see, before engagement metrics optimized for outrage, there was serendipity.

PokeAround brings that back—built on Elixir, powered by Bluesky's firehose, with on-device ML that doesn't phone home.

**[Live Docs](https://notactuallytreyanastasio.github.io/poke_around/)** | **[Decision Graph](https://notactuallytreyanastasio.github.io/poke_around/graph.html)**

---

## The Problem

Social media killed link discovery. Everything optimized for engagement means you see the same viral content as everyone else. RSS died. StumbleUpon shut down. Reddit became a popularity contest.

Meanwhile, interesting people are still sharing interesting things—just buried under algorithmic noise.

## The Solution

Tap directly into the firehose. Bluesky publishes every single post in real-time via the AT Protocol. That's ~31 posts per second, 24/7, from millions of users. Raw, unfiltered, chronological.

The challenge: most of it is noise. The opportunity: build filters that surface signal.

---

## How We Built It

### Step 1: Connect to the Firehose

Bluesky's raw firehose (Jetstream) gives you post content, but not author metadata. You'd need to make an API call for every post to check follower counts—impossible at 31 posts/second.

Enter [Graze Turbostream](https://graze.social): a hydrated firehose that includes author profiles with each post. Followers, following, bio, account age—all inline. This is the foundation that makes quality filtering possible.

```elixir
# lib/poke_around/bluesky/firehose.ex
defmodule PokeAround.Bluesky.Firehose do
  use WebSockex

  def start_link(_) do
    WebSockex.start_link(
      "wss://api.graze.social/turbostream",
      __MODULE__,
      %{},
      name: __MODULE__
    )
  end

  def handle_frame({:text, msg}, state) do
    msg
    |> Jason.decode!()
    |> Parser.parse()
    |> broadcast()
    {:ok, state}
  end
end
```

Phoenix PubSub broadcasts every post to subscribers. The Extractor listens and decides what's worth keeping.

### Step 2: Define Quality

Here's the key insight: **author credibility is a better signal than content engagement**.

A link shared by someone with 5,000 followers who follows 200 people is probably more interesting than a link from a new account with 50 followers following 10,000. The first person has earned an audience. The second is likely a bot or spam account.

We encode this into filtering rules:

| Signal | Threshold | Why |
|--------|-----------|-----|
| Followers | >= 500 | You've built an audience |
| Following | <= 5,000 | Not follow-for-follow behavior |
| Account age | >= 1 year | Not a spam account created yesterday |
| Has bio | Required | Real people describe themselves |
| Post length | >= 50 chars | Actual commentary, not just a link |
| Hashtags | <= 1 | Spam posts are hashtag-heavy |
| Emojis | <= 1 | Quality posts aren't emoji soup |
| Link count | Exactly 1 | Multiple links = aggregator spam |

**Result: 97% of links get rejected.** What remains is genuinely interesting.

### Step 3: Score by Credibility

Links that pass filtering get scored 0-100:

```elixir
def calculate_score(%{author: author}) do
  followers = author.followers_count || 0
  following = author.follows_count || 1

  # Log scale for followers (diminishing returns)
  follower_score = :math.log10(max(followers, 1)) * 15

  # Bonus for curated taste (high follower/following ratio)
  ratio = followers / max(following, 1)
  ratio_bonus = min(ratio * 5, 20)

  min(round(follower_score + ratio_bonus), 100)
end
```

| Profile | Score | Reasoning |
|---------|-------|-----------|
| 1K followers / 200 following | 65 | Established, good ratio |
| 10K followers / 500 following | 80 | Large audience, selective |
| 100K followers / 100 following | 95 | Influential tastemaker |
| 500 followers / 400 following | 46 | Barely qualifies |

The log scale prevents mega-accounts from dominating. The ratio bonus rewards people who are selective about who they follow.

### Step 4: Classify with On-Device ML

Links need categories for browsing. We could use an LLM API, but that's slow, expensive, and sends your data to someone else's servers.

Instead: train a lightweight classifier locally using [Axon](https://github.com/elixir-nx/axon) (Elixir's neural network library) and run inference with [EXLA](https://github.com/elixir-nx/nx/tree/main/exla) (XLA bindings for hardware acceleration).

**The model:**
- Multi-label text classifier (bag-of-words → dense layers → sigmoid)
- 286K parameters, 1.14 MB on disk
- Trained on ~1,100 manually-tagged links
- 70-95% accuracy on common categories

**The speed:**
- 0.59ms per prediction on Apple M Max
- 1,700 predictions/second
- Fast enough to tag every incoming link in real-time

```elixir
# Training
mix poke.train --epochs 100 --min-tags 20

# The model architecture
def build_model(vocab_size, num_classes) do
  Axon.input("text", shape: {nil, vocab_size})
  |> Axon.dense(256, activation: :relu)
  |> Axon.dropout(rate: 0.3)
  |> Axon.dense(128, activation: :relu)
  |> Axon.dropout(rate: 0.2)
  |> Axon.dense(num_classes, activation: :sigmoid)
end
```

No cloud. No API keys. No data leaving your machine. Just matrix multiplication on your CPU.

### Step 5: Store Everything in Postgres

Links, tags, author metadata, language info—all in PostgreSQL with proper indexes:

```sql
-- Deduplication
CREATE UNIQUE INDEX links_url_hash_index ON links(url_hash);

-- Quality queries
CREATE INDEX links_score_index ON links(score);

-- Language filtering (GIN for array overlap)
CREATE INDEX links_langs_index ON links USING GIN(langs);

-- Tag lookups
CREATE INDEX link_tags_link_id_index ON link_tags(link_id);
```

Ecto handles the ORM layer. Phoenix contexts keep the business logic organized.

### Step 6: Build the UI

A LiveView interface styled like classic Mac OS (System 7 era). Why? Because it's fun, and because the retro aesthetic matches the "remember when the internet was good?" vibe.

- **Bag of Links**: 50 random quality links, shuffled
- **Tag Browsing**: Click a topic, see links
- **Language Filter**: English, Spanish, Portuguese, etc.

LiveView means real-time updates without writing JavaScript. Click a link, it opens in a new tab and increments the stumble count server-side.

### Step 7: Integrate with ATProto

This is where it gets interesting. Bluesky isn't just a social network—it's built on the [AT Protocol](https://atproto.com/), a decentralized foundation where users own their data.

PokeAround speaks ATProto natively:

- **OAuth 2.0** with PAR (Pushed Authorization Requests), PKCE, and DPoP (Demonstration of Proof-of-Possession)
- **PDS Sync** publishes high-quality links to your Personal Data Server
- **Custom Lexicons** define `space.pokearound.link` and `space.pokearound.bookmark` record types

Your discoveries become portable. Export them. Move them to another PDS. Build on top of them.

```elixir
# Sync links scoring 50+ to your PDS
config :poke_around, PokeAround.ATProto,
  sync_enabled: true,
  sync_min_score: 50
```

---

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
│  Firehose (GenServer + WebSockex)                               │
│  • Auto-reconnect on disconnect                                 │
│  • Stats tracking (messages/sec)                                │
│  • PubSub broadcast to subscribers                              │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  Extractor (GenServer)                                          │
│  • Quality filtering (8 signals)                                │
│  • Credibility scoring (log + ratio)                            │
│  • Domain banning (shorteners)                                  │
│  • ~3% pass rate                                                │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  PostgreSQL                                                     │
│  • links table (URL, author, score, metadata)                   │
│  • tags table (normalized slugs, usage counts)                  │
│  • link_tags join table (many-to-many)                          │
└───────────────────────────────┬─────────────────────────────────┘
                                │
              ┌─────────────────┼─────────────────┐
              │                 │                 │
              ▼                 ▼                 ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│  Axon Tagger    │  │  PDS Sync       │  │  Stumble UI     │
│                 │  │                 │  │                 │
│  • Nx/EXLA      │  │  • OAuth 2.0    │  │  • LiveView     │
│  • 1,700/sec    │  │  • DPoP signing │  │  • Retro Mac OS │
│  • 286K params  │  │  • Custom lexs  │  │  • Real-time    │
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

## Tech Stack

| Layer | Technology | Why |
|-------|------------|-----|
| Language | Elixir | Concurrency, fault tolerance, LiveView |
| Framework | Phoenix | Channels, PubSub, LiveView |
| ML | Axon + Nx + EXLA | On-device, fast, Elixir-native |
| Database | PostgreSQL | Reliable, GIN indexes for arrays |
| WebSocket | WebSockex | Firehose connection |
| Protocol | ATProto | Decentralized, user-owned data |

---

## Quick Start

```bash
git clone https://github.com/notactuallytreyanastasio/poke_around
cd poke_around

# Install deps, create DB, run migrations
mix setup

# Start the server (firehose connects automatically)
mix phx.server

# Visit http://localhost:4000/stumble
```

Links start flowing within seconds.

## Training the Tagger

```bash
# Train on existing tagged links (min 20 examples per tag)
mix poke.train --epochs 100 --min-tags 20

# Test predictions
mix poke.train --test

# Run tagger on untagged links
mix poke.tag_axon --batch 50 --threshold 0.25
```

More data = better model. Retrain periodically as you accumulate tagged links.

## Configuration

```elixir
# config/config.exs

config :poke_around, PokeAround.AI.AxonTagger,
  enabled: true,
  model_path: "priv/models/tagger",
  threshold: 0.25,
  batch_size: 20,
  interval_ms: 10_000,
  langs: ["en"]

config :poke_around, PokeAround.ATProto,
  sync_enabled: false,  # Enable to publish to your PDS
  sync_min_score: 50
```

---

## Performance

From a 10-minute production run:

| Metric | Value |
|--------|-------|
| Firehose throughput | 31 msg/sec |
| Links extracted | 4,133 |
| Links qualified | 136 (3.3%) |
| Axon inference | 1,700 pred/sec |
| E2E latency | < 100ms |

**Top tags discovered:** weather, politics, tech, news, music, football, climate

---

## Project Structure

```
lib/poke_around/
├── bluesky/
│   ├── firehose.ex          # WebSocket client
│   ├── parser.ex            # Event parsing
│   └── supervisor.ex
├── links/
│   ├── extractor.ex         # Quality filtering + scoring
│   └── link.ex              # Ecto schema
├── ai/
│   ├── axon/
│   │   └── text_classifier.ex   # Model definition + training
│   ├── axon_tagger.ex       # Production GenServer
│   └── supervisor.ex
├── atproto/
│   ├── client.ex            # PDS operations
│   ├── oauth.ex             # OAuth flow
│   ├── dpop.ex              # JWT signing
│   └── sync.ex              # Background worker
├── tags.ex                  # Tag context
└── links.ex                 # Link context

lib/poke_around_web/live/
└── stumble_live.ex          # The UI
```

---

## Future Work

- [ ] **Feed Generator** — Publish as a Bluesky custom feed
- [ ] **RSS Export** — Topic-based RSS feeds
- [ ] **Engagement Decay** — Re-score based on likes/reposts over time
- [ ] **Bookmark Sync** — Save discoveries to your PDS
- [ ] **Ad Detection** — Filter promotional content

---

## Why "PokeAround"?

Because that's what you do with it. Poke around the internet. Discover things serendipitously. Like we used to.

---

## Requirements

- Elixir 1.15+ / OTP 26
- PostgreSQL 14+
- ~50MB disk

No external APIs. Everything runs locally.

## License

MIT
