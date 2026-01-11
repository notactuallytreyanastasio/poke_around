# ATProto Integration

PokeAround integrates with the AT Protocol (ATProto) to store curated links on the decentralized network and enable user bookmarking. This document covers the complete ATProto implementation.

## Overview

The integration provides:
- **OAuth Authentication**: Full ATProto OAuth with PAR, PKCE, and DPoP
- **PDS Sync**: Background worker that syncs high-quality links to a service account's Personal Data Server
- **Custom Lexicons**: `space.pokearound.link` and `space.pokearound.bookmark` record types
- **User Bookmarking**: (Planned) Users can save bookmarks to their own PDS

## Architecture

```
lib/poke_around/atproto/
├── client.ex       # High-level PDS client (create/get/list/delete records)
├── dpop.ex         # DPoP JWT generation (ES256)
├── discovery.ex    # Server metadata discovery (.well-known endpoints)
├── lexicon.ex      # Elixir structs for space.pokearound.* records
├── oauth.ex        # OAuth flow coordinator (PAR, token exchange, refresh)
├── pkce.ex         # PKCE S256 implementation
├── session.ex      # Ecto schema for session persistence
├── supervisor.ex   # Supervisor for ATProto workers
├── sync.ex         # Background GenServer for PDS sync
└── tid.ex          # TID (Timestamp Identifier) generation
```

## OAuth Implementation

ATProto uses a strict OAuth 2.0 flow with several mandatory security features.

### Security Requirements

| Feature | Description |
|---------|-------------|
| **PAR** | Pushed Authorization Request - all auth requests go through `/oauth/par` first |
| **PKCE S256** | Proof Key for Code Exchange using SHA-256 challenge |
| **DPoP** | Demonstrating Proof of Possession - every request includes a signed JWT proving key ownership |
| **Nonce Rotation** | Servers may require nonce values that must be included in subsequent requests |

### OAuth Flow

1. **Resolve Identity** (`discovery.ex:resolve_handle/1`)
   - Handle → DID via DNS TXT record or HTTP well-known
   - DID → PDS URL via DID document

2. **Server Discovery** (`discovery.ex:discover_auth_server/1`)
   - Fetch `/.well-known/oauth-protected-resource`
   - Fetch `/.well-known/oauth-authorization-server`

3. **PAR Request** (`oauth.ex:initiate_par/6`)
   ```
   POST /oauth/par
   Headers: Content-Type: application/x-www-form-urlencoded, DPoP: <jwt>
   Body: client_id, response_type=code, redirect_uri, scope, state,
         code_challenge, code_challenge_method=S256, login_hint=<did>
   Response: { request_uri: "urn:ietf:params:oauth:request_uri:..." }
   ```

4. **User Authorization**
   - Redirect to: `{auth_endpoint}?client_id=...&request_uri=...`
   - User authenticates on Bluesky

5. **Token Exchange** (`oauth.ex:exchange_code/3`)
   ```
   POST /oauth/token
   Headers: Content-Type: application/x-www-form-urlencoded, DPoP: <jwt>
   Body: grant_type=authorization_code, code, redirect_uri, client_id, code_verifier
   Response: { access_token, refresh_token, expires_in, sub }
   ```

### DPoP Implementation

DPoP tokens are ES256-signed JWTs that prove possession of a private key. Located in `dpop.ex`.

```elixir
# Generate keypair (once per auth session)
{private_key, public_jwk} = DPoP.generate_keypair()

# Create proof for token endpoint (no ath)
jwt = DPoP.create_proof(private_key, public_jwk, :post, url, nonce)

# Create proof for resource requests (includes access token hash)
jwt = DPoP.create_proof_with_ath(private_key, public_jwk, :get, url, access_token, nonce)
```

**DPoP JWT Structure:**
```json
{
  "header": {
    "typ": "dpop+jwt",
    "alg": "ES256",
    "jwk": { "kty": "EC", "crv": "P-256", "x": "...", "y": "..." }
  },
  "payload": {
    "jti": "<unique-id>",
    "htm": "POST",
    "htu": "https://bsky.social/oauth/token",
    "iat": 1704067200,
    "exp": 1704067500,
    "nonce": "<server-provided>",
    "ath": "<sha256(access_token)>"  // Only for resource requests
  }
}
```

### PKCE Implementation

PKCE prevents authorization code interception. Located in `pkce.ex`.

```elixir
{verifier, challenge} = PKCE.generate()
# verifier: 43-128 character random string
# challenge: base64url(sha256(verifier))
```

### Session Persistence

Sessions are stored in PostgreSQL via `PokeAround.ATProto.Session` (`session.ex`).

**Schema:**
| Field | Type | Description |
|-------|------|-------------|
| `user_did` | string | User's DID (unique) |
| `handle` | string | User's handle |
| `access_jwt` | text | Encrypted access token |
| `refresh_jwt` | text | Encrypted refresh token |
| `pds_url` | string | User's PDS URL |
| `dpop_keypair_json` | text | Serialized ES256 keypair |
| `access_expires_at` | datetime | Token expiration |

## TID (Timestamp Identifier)

TIDs are 13-character base32-sortable identifiers used as record keys. Located in `tid.ex`.

**Format:**
- 53 bits: microseconds since Unix epoch
- 10 bits: clock identifier (random per process)

```elixir
# Generate a TID
tid = TID.generate()  # e.g., "3k2yihx5l3s22"

# Parse back to datetime
{:ok, dt} = TID.to_datetime(tid)
```

**Character Set:** `234567abcdefghijklmnopqrstuvwxyz` (base32-sortable)

## Custom Lexicons

Lexicon schemas define record types for ATProto. Located in `priv/lexicons/`.

### space.pokearound.link

Curated link record stored in the service account's repo.

```json
{
  "lexicon": 1,
  "id": "space.pokearound.link",
  "defs": {
    "main": {
      "type": "record",
      "key": "tid",
      "record": {
        "type": "object",
        "required": ["url", "createdAt"],
        "properties": {
          "url": { "type": "string", "format": "uri", "maxLength": 2048 },
          "title": { "type": "string", "maxLength": 500 },
          "description": { "type": "string", "maxLength": 2000 },
          "domain": { "type": "string", "maxLength": 256 },
          "imageUrl": { "type": "string", "format": "uri" },
          "tags": { "type": "array", "maxLength": 10 },
          "langs": { "type": "array", "maxLength": 5 },
          "score": { "type": "integer", "minimum": 0, "maximum": 100 },
          "sourcePost": { "type": "ref", "ref": "#sourcePost" },
          "createdAt": { "type": "string", "format": "datetime" }
        }
      }
    }
  }
}
```

### space.pokearound.bookmark

User bookmark record stored in the user's own repo.

```json
{
  "lexicon": 1,
  "id": "space.pokearound.bookmark",
  "defs": {
    "main": {
      "type": "record",
      "key": "tid",
      "properties": {
        "url": { "type": "string", "format": "uri" },
        "title": { "type": "string", "maxLength": 500 },
        "domain": { "type": "string" },
        "note": { "type": "string", "maxLength": 1000 },
        "personalTags": { "type": "array", "maxLength": 10 },
        "pokeAroundUri": { "type": "string", "format": "at-uri" },
        "createdAt": { "type": "string", "format": "datetime" }
      }
    }
  }
}
```

## PDS Client

High-level client for PDS operations. Located in `client.ex`.

```elixir
# Get a session (auto-refreshes if expired)
{:ok, session} = Client.get_session(did)

# Create a record
{:ok, %{uri: uri, cid: cid}, session} = Client.create_record(
  session,
  "space.pokearound.link",
  record,
  rkey: TID.generate()
)

# List records
{:ok, records, cursor, session} = Client.list_records(
  session,
  "space.pokearound.link",
  limit: 50
)

# Delete a record
{:ok, session} = Client.delete_record(session, "space.pokearound.link", rkey)
```

## PDS Sync Worker

Background GenServer that syncs high-quality links to PDS. Located in `sync.ex`.

### Configuration

```elixir
# config/runtime.exs
config :poke_around, PokeAround.ATProto,
  sync_min_score: 50,      # Only sync links with score >= 50
  sync_enabled: true       # Enable/disable sync
```

### Behavior

- Runs every 60 seconds
- Processes links in batches of 20
- Only syncs links where `score >= min_score` and `sync_status IS NULL`
- Updates link with `at_uri` and `synced_at` on success
- Marks link as `sync_status: "failed"` on error

### API

```elixir
# Manually trigger sync
Sync.sync_now()

# Sync a single link
{:ok, session} = Sync.sync_link(link_id)

# Get stats
%{synced_count: 150, failed_count: 2, last_sync: ~U[...]} = Sync.stats()
```

## Auth Controller

Web controller for OAuth flow. Located in `lib/poke_around_web/controllers/atproto_auth_controller.ex`.

### Routes

```elixir
# router.ex
scope "/auth", PokeAroundWeb do
  get "/bluesky", ATProtoAuthController, :login
  get "/bluesky/callback", ATProtoAuthController, :callback
  delete "/logout", ATProtoAuthController, :logout
end
```

### Login Flow

1. `GET /auth/bluesky?handle=user.bsky.social&popup=true`
2. Stores auth state in session
3. Redirects to Bluesky authorization

### Callback Handling

- Verifies state matches
- Exchanges code for tokens
- Persists session to database
- For popup mode: posts `atproto_auth_success` message to opener

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ATPROTO_CLIENT_ID` | Your OAuth client_id URL | Required |
| `ATPROTO_SYNC_ENABLED` | Enable PDS sync | `false` |
| `ATPROTO_SYNC_MIN_SCORE` | Minimum score to sync | `50` |

### Client ID

The `client_id` must be a publicly accessible URL that returns a JSON document:

```json
{
  "client_id": "https://pokearound.space/client-metadata.json",
  "client_name": "PokeAround",
  "client_uri": "https://pokearound.space",
  "redirect_uris": ["https://pokearound.space/auth/bluesky/callback"],
  "grant_types": ["authorization_code", "refresh_token"],
  "response_types": ["code"],
  "scope": "atproto transition:generic",
  "token_endpoint_auth_method": "none",
  "dpop_bound_access_tokens": true
}
```

## Database Schema

### atproto_sessions

```sql
CREATE TABLE atproto_sessions (
  id BIGSERIAL PRIMARY KEY,
  user_did VARCHAR NOT NULL UNIQUE,
  handle VARCHAR,
  access_jwt TEXT,
  refresh_jwt TEXT,
  pds_url VARCHAR,
  dpop_keypair_json TEXT,
  access_expires_at TIMESTAMP,
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);
```

### links (ATProto fields)

```sql
ALTER TABLE links ADD COLUMN at_uri VARCHAR;
ALTER TABLE links ADD COLUMN synced_at TIMESTAMP;
ALTER TABLE links ADD COLUMN sync_status VARCHAR;
```

## Dependencies

```elixir
# mix.exs
{:jose, "~> 1.11"}  # JWT/JWK handling for DPoP
{:req, "~> 0.5"}    # HTTP client (already included)
```

## Error Handling

### Nonce Rotation

The ATProto auth servers may require a `use_dpop_nonce` response. The implementation handles this automatically:

```elixir
case response do
  {:ok, %{status: 401, body: %{"error" => "use_dpop_nonce"}, headers: headers}} ->
    nonce = get_dpop_nonce(headers)
    # Retry request with nonce
end
```

### Token Refresh

Sessions are auto-refreshed when expired:

```elixir
def get_session(did) do
  case load_from_db(did) do
    {:ok, session} when session_expired?(session) ->
      {:ok, refreshed} = OAuth.refresh_session(session)
      save_session(refreshed)
      {:ok, refreshed}
    result -> result
  end
end
```

## Future Work

- [ ] Feed Generator (`app.bsky.feed.getFeedSkeleton`)
- [ ] User bookmark syncing to personal repos
- [ ] Bookmarklet popup OAuth flow
- [ ] RSS feeds with ATProto integration
