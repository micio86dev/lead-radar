# Reddit Data API: verified guide (checked 2026-11-03)

This page documents the official Reddit Data API as it stands now, why attempts commonly fail, and what
Lead Radar implements once working credentials exist. Every claim carries its source; where a primary
page refuses this host (`403`), the secondary source is named.

## 1. Reality check: new public API access is closed

Reddit is moving public Data API apps and bots to its Developer Platform (Devvit), described by Reddit
as "part of efforts to reduce scraping and automated abuse". Its changelog of 8 October 2026 sets:

| Date | What happens |
|---|---|
| **31 October 2026** | New requests for public API access are no longer accepted |
| 12 January 2027 | Removal begins for apps/users that have not registered or answered Reddit's outreach |
| **March 2027** | Remaining public API access ends |

Consequences today:

- **A new API key cannot be obtained.** This is the most likely reason repeated attempts failed,
  independently of the technical steps below.
- Apps that were already approved keep free access at **100 queries per minute per OAuth client id**
  until access ends.
- **Commercial use requires Reddit's permission and a separate agreement** (Data API Terms §3.1: "If
  you are interested in using the Data APIs for commercial purposes … you will need to enter into a
  separate agreement with Reddit").
- Alternatives: Devvit (apps that run *inside* Reddit — not server-side discovery), Reddit for
  Researchers (academic), a commercial contract, or a licensed monitoring provider.

Sources: Reddit Data API Terms (effective 19 June 2023, revised 20 July 2026),
`https://www.redditinc.com/policies/data-api-terms`; closure dates and 100 QPM as reported for Reddit's
8 October 2026 changelog and Responsible Builder Policy in `https://boomreddit.com/glossary/reddit-api/`
(Reddit's own help pages answer `403` to unauthenticated requests from this host).

## 2. If you already have an approved app: the exact calls

Prerequisites: an existing app under `https://www.reddit.com/prefs/apps`; type **script** for a personal
server-side integration; the client id is shown under the app name, the secret next to it. Redirect URI
`http://localhost:8080` is required by the form and unused for script apps.

### Step 1 — app-only token (simplest, read-only public content)

```bash
curl -s -u "$REDDIT_CLIENT_ID:$REDDIT_CLIENT_SECRET" \
  -A "leadradar:local:v0.1 (by /u/$REDDIT_USERNAME)" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  https://www.reddit.com/api/v1/access_token
```

Response: `{ "access_token": …, "token_type": "bearer", "expires_in": 3600, "scope": "…" }`.
Tokens last **one hour** and app-only tokens never include a refresh token.

### Step 2 — acting as your user (password grant, script apps only)

Same endpoint and Basic auth, body
`grant_type=password&username=USER&password=PASS`. This is the flow that fails with `invalid_grant` when
the account has two-factor authentication enabled.

### Step 3 — refresh (only if you asked for `duration=permanent`)

Same endpoint, body `grant_type=refresh_token&refresh_token=TOKEN`.

### Step 4 — call the API on `oauth.reddit.com`

```bash
curl -s -A "$USER_AGENT" -H "Authorization: bearer $TOKEN" \
  "https://oauth.reddit.com/r/recruiting/search?q=%22language+barrier%22&restrict_sr=1&sort=relevance&t=year&limit=25&raw_json=1"
```

- Host is **`oauth.reddit.com`**, not `www.reddit.com`, when using a bearer token.
- `User-Agent` is mandatory and must be unique and descriptive:
  `<platform>:<app id>:<version string> (by /u/<reddit username>)`. Default library agents
  (`python-requests`, `urllib`, `Java`, …) are throttled or blocked, and misrepresenting one is a ban
  reason.
- Search parameters: `q`, `restrict_sr=1` (search inside the subreddit), `sort=relevance|new|top`,
  `t=hour|day|week|month|year|all`, `limit` up to 100, `after=<fullname>` for pagination,
  `raw_json=1` to avoid HTML entities.
- Response shape: `{ "kind": "Listing", "data": { "after": …, "children": [ { "kind": "t3", "data": {
  title, selftext, permalink, created_utc, score, num_comments, subreddit, author, … } } ] } }`.

### Step 5 — rate limits and errors

Headers on every response: `X-Ratelimit-Used`, `X-Ratelimit-Remaining`, `X-Ratelimit-Reset` (seconds).
The limit is 100 queries/minute per client id, averaged over a 10-minute window; older documentation
says 60.

| Status | Meaning | Fix |
|---|---|---|
| 401 | bad client credentials, expired/invalid token | check Basic auth, re-request the token |
| 403 | blocked user agent, missing approval, restricted content | use a unique UA, verify the app is approved |
| 429 | rate limit | sleep until `X-Ratelimit-Reset`, then retry slowly |
| `unsupported_grant_type` | wrong `grant_type` or wrong content type | send `application/x-www-form-urlencoded` |
| `invalid_grant` | wrong username/password, 2FA, reused code, expired code | fix credentials or use the code flow |

### Step 6 — diagnose before integrating

```bash
./scripts/reddit-token-check.sh
```

The script prompts for the client id (visible) and secret (hidden), requests an app-only token, then
performs one search call. It prints only statuses, scopes, expiry, rate-limit headers and the number of
posts returned — never the secret or the token. If it fails, the message names the likely cause.

## 3. Why attempts commonly fail

1. A default User-Agent (`python-requests`, `curl` default, `urllib`) — the API throttles it.
2. `grant_type=client_credentials` from an **installed** app (no secret) — use
   `https://oauth.reddit.com/grants/installed_client` with a `device_id` instead.
3. Two-factor authentication enabled on the account combined with the password grant.
4. Calling `www.reddit.com` with a bearer token instead of `oauth.reddit.com`.
5. Missing `Content-Type: application/x-www-form-urlencoded` on the token request.
6. Reusing an authorization code (single use) or an expired token (one hour).
7. No approval under the Responsible Builder Policy — and since 31 October 2026 new requests are closed.
8. Exceeding 100 QPM per client id.

## 4. What Lead Radar implements once credentials work

- A new `SourceProvider` (`reddit_official`) beside Apify: `REDDIT_CLIENT_ID`, `REDDIT_CLIENT_SECRET`,
  `REDDIT_USERNAME`, `REDDIT_PASSWORD` or `REDDIT_REFRESH_TOKEN`, and a mandatory `REDDIT_USER_AGENT`.
- A token cache that refreshes 60 seconds before expiry; 429 and `X-Ratelimit-Reset` drive backoff, never
  a busy loop.
- Per-community search with `restrict_sr=1` and the quoted phrases already configured, mapped to the same
  `ImportPost` path (title, selftext, permalink → url, created_utc → published_at, score/num_comments →
  engagement, subreddit → community).
- Wiremock contract tests for token, search, pagination and every error above; no live credential in CI.
- The spend guard does not apply (no provider charge); the rate limiter does.
- Data minimisation: only fields a lead needs, the existing `DELETE /api/v1/opportunities/:id` and
  `db purge` for retention, and no use of collected text to train models (Data API Terms §2.4, §3.2).

## 5. Current recommendation

Until an approved app or a commercial agreement exists, the compliant routes are the authorized
provider already wired (Apify Actor, used with the operator's explicit risk decision) or manual JSON
import. Devvit is not a substitute for server-side discovery: it runs apps inside Reddit.
