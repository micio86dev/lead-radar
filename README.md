# Lead Radar

[![CI](https://github.com/micio86dev/lead-radar/actions/workflows/ci.yml/badge.svg)](https://github.com/micio86dev/lead-radar/actions/workflows/ci.yml)

Multi-tenant B2B opportunity discovery: authorized public sources -> deterministic filtering ->
typed AI decisions -> deterministic scoring -> human-reviewed engagement suggestions.

Lead Radar never publishes, comments, DMs, upvotes or follows. Every outbound action is manual and
recorded by a human.

## Repositories

| Path | Contents |
|---|---|
| [`lead-radar-backend`](https://github.com/micio86dev/lead-radar-backend) | Rust modular monolith (Axum API + worker, SQLx/SQLite) |
| [`lead-radar-frontend`](https://github.com/micio86dev/lead-radar-frontend) | Astro + Vue 3 + TypeScript dashboard (Bun) |

Both are Git submodules with their own history. The root repository owns Compose, documentation,
CI orchestration, scripts and environment examples only; it contains no application source.

## Quick start

```bash
cp .env.example .env          # fill provider credentials you actually have
make up                       # api + worker + frontend, SQLite volume
make migrate                  # versioned migrations (also run by the api container)
make seed                     # idempotent seed data
open http://localhost:4321
```

Daily work happens in **/reply-queue**: one screen per lead with the draft inline, copy, open thread and a
single "I posted it" action that records the publication. The optional Chrome extension
([`extension/`](extension/README.md)) brings the same draft onto the Reddit page and pre-fills the comment
box. Nothing is published automatically.

Provider credentials are optional. Without them the application runs the full pipeline against the
built-in mock providers and the dashboard reports the affected providers as `unconfigured`.

```bash
make test                     # backend + frontend
make test-e2e                 # Playwright end-to-end suite
make lint                     # cargo fmt/clippy + prettier check + typecheck
make reset-db                 # DESTRUCTIVE: deletes the local SQLite volume
```

Full documentation: [`docs/`](docs/). Start with
[`docs/architecture.md`](docs/architecture.md), then [`docs/development.md`](docs/development.md).

## Status

The implementation status of every product area (implemented, tested offline, tested against live
providers, blocked) is tracked in [`docs/status.md`](docs/status.md). It is generated from observed
test runs, not from intentions.

## License

[PolyForm Noncommercial License 1.0.0](LICENSE): free for noncommercial use. Commercial use requires a
paid license — see [`COMMERCIAL.md`](COMMERCIAL.md). This is a source-available license, not an OSI
open-source license.

## Non-negotiables

1. No automatic publication or third-party account interaction.
2. No unauthorized scraping; communities and Actors stay `pending` until a human records validation.
3. No invented Actor IDs, model IDs, endpoints or prices: everything comes from configuration.
4. Spend safety: every billable action passes the cost guard before it is queued.
5. Secrets only in `.env` / environment variables, never in the repository or the frontend bundle.
6. Local commits only; no remote is configured and nothing is pushed.
