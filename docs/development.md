# Development

## Prerequisites

| Tool | Version used | Notes |
|---|---|---|
| Rust | 1.89.0 | pinned by `lead-radar-backend/rust-toolchain.toml` |
| Bun | 1.4.2 | frontend package manager and runner |
| Node.js | 24.18.0 | runs the built Astro server |
| SQLite | 3.35+ | `RETURNING` and partial indexes are used |
| Docker | 29.x with Compose v2 | optional, for the full stack |

## First run

```bash
cp .env.example .env         # fill only the credentials you actually have
make migrate
make seed
make dev-api                 # terminal 1
make dev-worker              # terminal 2
make dev-frontend            # terminal 3 -> http://localhost:4321
```

Without provider credentials, set `DECISION_PROVIDER=mock`, `GENERATIVE_PROVIDER=mock` and
`SOURCE_PROVIDER=mock` to exercise the whole pipeline offline. Mocks are rejected when
`APP_ENV=production`.

## Repository layout

```
lead-radar/                  # root: Compose, docs, CI, scripts, env examples
  lead-radar-backend/        # submodule: Rust crate (api, worker, db, healthcheck)
  lead-radar-frontend/       # submodule: Astro + Vue dashboard
```

Both submodules are local repositories. No remote is configured and nothing is pushed. To attach one
later:

```bash
git -C lead-radar-backend remote add origin <url>
git -C lead-radar-frontend remote add origin <url>
git submodule sync --recursive
```

## Common commands

```bash
make test          # backend tests + frontend typecheck/lint/tests
make test-backend
make test-frontend
./scripts/e2e-local.sh   # isolated stack + Playwright
make lint          # fmt check + clippy -D warnings + prettier + typecheck
make fmt
```

## Secrets

Never paste a credential into a shell command, an issue or a chat: it ends up in shell history, process
lists or logs. Use the hidden-input helper, which validates the documented shape before writing and
prints only PASS/FAIL:

```bash
./scripts/set-secret.sh JEV_API_KEY      # sk-glm5-…
./scripts/set-secret.sh APIFY_API_TOKEN  # apify_api_…
./scripts/set-secret.sh QWEN_API_KEY     # OpenAI-compatible key
./scripts/set-secret.sh LAYA_API_KEY     # lsk_…
```

Then recreate the containers so they read the new value:

```bash
docker compose up -d --force-recreate api worker frontend
```

Verify a provider with one explicit, possibly billable probe (never on page render):

```bash
set -a; . ./.env; set +a
curl -s -X POST http://localhost:8080/api/v1/providers/jev/test \
  -H "Authorization: Bearer $DEV_API_TOKEN" -H 'Content-Type: application/json' -d '{}'
```

A `401 invalid_api_key` from Jev means the value is not a full key: the documented form starts with
`sk-glm5-` and is shown only once in the provider dashboard.

## Conventions

- Conventional Commits; one reviewable work unit per commit with `Risk:` in the body.
- Application artifacts (code, comments, commits, docs) are in English.
- Tests and documentation ship with the behaviour they describe.
- Never commit `.env`, databases or credentials. `db token <plaintext>` prints the hash to store.

## Working on the pipeline

1. Import a post: `POST /api/v1/import/json` (see `docs/api.md`).
2. Watch the worker: `GET /api/v1/jobs`, then `GET /api/v1/opportunities`.
3. Inspect the decision and score on the detail endpoint or the opportunity page.
4. Trigger `POST /api/v1/opportunities/:id/generate-comments`, then review in `/review`.

The worker must be running; `strap` without it leaves jobs queued, which is visible rather than silent.
