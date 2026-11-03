# AGENTS.md — Lead Radar (root repository)

This repository orchestrates two Git submodules:

- `lead-radar-backend` — Rust (Axum, Tokio, SQLx, SQLite) API + worker, modular monolith.
- `lead-radar-frontend` — Astro + Vue 3 + TypeScript (strict), Bun.

The root owns Docker Compose, shared documentation, CI orchestration, development
scripts, environment examples, integration/E2E orchestration and architecture
decisions. It owns no application source code.

## Non-negotiable product rules

1. **No automatic publication.** The product never comments, DMs, uploads,
   follows, votes or otherwise interacts with third-party accounts. Manual
   publication recording is the only path after human approval.
2. **No unauthorized scraping.** Communities and Actors stay `pending`/disabled
   until validation is recorded. Never bypass authentication, CAPTCHAs, rate
   limits or platform protections.
3. **No invented integrations.** Actor IDs, model IDs, endpoints and prices must
   come from configuration or verified documentation. Never invent provider
   capabilities, credentials or test results.
4. **Spend safety.** Every billable action passes the cost guard before it is
   queued. No silent retry of a potentially billed run.
5. **Secrets never enter the repo.** Only `.env` (untracked) and environment
   variables. `.env.example` documents names and safe defaults only.
6. **Never push.** Commit locally only; remotes are configured by the human.

## Working conventions

- Application artifacts (code, comments, commit messages, docs) are in English.
- Conventional Commits. One reviewable work unit per commit (~400 changed lines).
- Tests and documentation ship in the same commit as the behavior they describe.
- Every commit message body states `Risk: none` or `Risk: item N (reason)` using
  the high-risk list of the harness contract; high-risk units get their own commit.
- Run `make lint` and `make test` before claiming a milestone is complete.

## Repository layout

```
lead-radar/
  lead-radar-backend/     # submodule
  lead-radar-frontend/    # submodule
  docs/                   # shared documentation
  scripts/                # dev + orchestration scripts
  docker-compose.yml      # default (production-like) profile
  docker-compose.test.yml # test profile
  Makefile
  .env.example
```

## Submodule notes

Both submodules are local repositories created without a remote. To attach a
remote later:

```
git -C lead-radar-backend remote add origin <url>
git -C lead-radar-frontend remote add origin <url>
git submodule sync --recursive
```

## Local hooks

`core.hooksPath` is set to `.githooks` for these repositories so the globally
templated `gga` pre-commit hook (AI review on every staged diff) does not run on
each of the many small work-unit commits of this build. Review happens through
`make lint`, `make test` and explicit review passes. This is a per-repository
setting and does not affect other projects.
