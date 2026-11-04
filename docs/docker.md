# Docker

## Images

| Image | Base | Notes |
|---|---|---|
| `lead-radar/backend:0.1.0` | `rust:1.89.0-bookworm` → `debian:bookworm-slim` | builds all four binaries; runs as UID 10001; `/data` is the writable volume |
| `lead-radar/frontend:0.1.0` | `oven/bun:1.4.2` → `node:24.18.0-alpine` | Astro standalone server on port 4321, runs as `node` |

No `latest` tags. Backend build is `--locked`; frontend install is `--frozen-lockfile`.

## Compose

`docker-compose.yml` defines `api`, `worker` and `frontend`, a named volume `lead-radar-data` mounted at
`/data`, healthchecks for api and frontend, and `worker`/`frontend` waiting for a healthy api.

```bash
cp .env.example .env
make up            # build and start
make logs
make down          # keeps the volume
make reset-db      # DESTRUCTIVE: deletes the volume
```

Inside Compose, `DATABASE_URL` is overridden to `sqlite:///data/lead-radar.db?mode=rwc`, and the
frontend receives `API_INTERNAL_URL=http://api:8080`.

## Migrations and seeds

Both binaries migrate on startup. Explicit commands:

```bash
make migrate   # docker compose run --rm api /usr/local/bin/db migrate
make seed      # docker compose run --rm api /usr/local/bin/db seed
```

Seeds are idempotent; running them twice changes nothing.

## Test profile

`docker-compose.test.yml` runs `cargo test --all-targets` in `lead-radar-backend/Dockerfile.test` and
`typecheck && lint && test` in `lead-radar-frontend/Dockerfile.test`, with offline providers.

```bash
docker compose -f docker-compose.test.yml up --build --abort-on-container-exit
```

## Local development without Docker

```bash
cd lead-radar-backend && cp ../.env.example ../.env   # once
cargo run --bin api
cargo run --bin worker     # second terminal
cd lead-radar-frontend && bun install && bun run dev
```

## Volumes and permissions

The container starts as root only to repair the ownership of the mounted data volume and then drops to
UID 10001 with `setpriv` before running the API, the worker or the stack entrypoint. That is what makes
a host-provided volume (Railway, a named Docker volume) usable: SQLite cannot create its file in a
root-owned directory. The application itself always runs unprivileged. If you bind-mount a host
directory instead of the named volume, make it writable by that UID (or run with `user:` in Compose).
