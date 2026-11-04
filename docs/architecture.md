# Architecture

Lead Radar is a modular monolith: one Rust crate that produces four binaries (`api`, `worker`, `db`,
`healthcheck`) plus an Astro/Vue dashboard that only talks to the API server-side.

```
                 ┌──────────────────────────────┐
 browser ──────► │ Astro SSR (lead-radar-frontend) │ ── server-side Bearer token ──┐
                 └──────────────────────────────┘                                │
                                                                                  ▼
                 ┌───────────────────────────────┐        ┌──────────────────────────────┐
                 │ api binary (Axum, /api/v1)     │◄──────►│ SQLite (WAL, one writer)      │
                 └───────────────────────────────┘        └──────────────────────────────┘
                                                                  ▲
                 ┌───────────────────────────────┐                │
                 │ worker binary (durable jobs)   │────────────────┘
                 └───────────┬───────────────────┘
                             │ provider traits only
         ┌───────────────────┼────────────────────┬──────────────────┐
         ▼                   ▼                    ▼                  ▼
   SourceProvider      DecisionProvider     DecisionProvider     GenerativeProvider
   (Apify | mock)      (Jev | mock)         (Laya, benchmark)    (Qwen | mock)
```

## Backend boundaries

| Path | Responsibility |
|---|---|
| `src/api/**` | routing, extractors, input validation, JSON mapping, error responses |
| `src/modules/**` | one directory per domain: models, SQL, rules (tenancy, sources, ingestion, decision, generative, qualification, comments, engagement, operations, benchmark) |
| `src/domain/**` | pure logic and vocabulary: enums, scoring, qualification, filtering, language, evidence, comment policy, benchmark metrics, job state machine, typed decisions |
| `src/providers/**` | external adapters behind traits; provider payloads never leak out |
| `src/worker/**` | job loop and handlers; handlers call modules, never `sqlx` directly |
| `src/auth.rs` | bearer token → `TenantContext` (tenant, user, role) |
| `src/config.rs` | environment parsing and validation |
| `src/seed.rs` | idempotent seeds |

Rules enforced by review and tests:

1. Tenant scoping: every tenant-owned query binds `tenant_id` from `TenantContext`.
2. No transaction across provider I/O: persist intent, call, persist outcome.
3. One SQLite writer: `Db.writer` has a single connection; reads use `Db.reader`.
4. Idempotency by database constraint: `UNIQUE(tenant_id, content_hash)`,
   `UNIQUE(tenant_id, post_id)` on leads, unique job `idempotency_key`.
5. Money: estimated and actual costs are separate columns/rows; unknown cost is `NULL`, never `0`.
6. Provider neutrality: only `DecisionProvider`, `GenerativeProvider` and `SourceProvider` are seams.
7. No `unsafe`; `unwrap`/`expect` only for provable invariants with a message.

## Pipeline

Manual JSON import (`POST /api/v1/import/json`) or Apify dataset ingestion creates
`discovered_posts` rows, deduplicated by content hash, and enqueues a `normalization` job. The worker
runs the configured keyword filter; relevant posts enqueue `decision_evaluation`, irrelevant ones are
audited and dropped before any paid call. A decision run calls the decision provider with the 13 typed
questions, persists the raw answers, then scores deterministically and qualifies the lead. Comment
generation is a separate, human-triggered job. Nothing in the codebase can publish.

## Frontend boundaries

`src/lib/api/client.ts` is the only module that calls `fetch`; every page is server-rendered, so the
bearer token stays on the server. Forms post to `/api/action`, a bounded action endpoint with an
allow-list of operations and no generic proxy. Helper logic (formatting, filters, sorting) lives in
`src/lib/**` with Vitest coverage.

## Versioning

- Rust toolchain pinned in `rust-toolchain.toml` (1.89.0), dependencies pinned by `Cargo.lock`.
- Bun dependencies pinned by `bun.lock`.
- Container images pinned by tag: `rust:1.89.0-bookworm`, `debian:bookworm-slim`,
  `oven/bun:1.4.2`, `node:24.18.0-alpine`.

## Projects and community matching

The product a tenant works on is a row, not a constant: `projects` holds a name, a summary in the
operator's own words, the public URLs that describe the product, and one project per tenant is the
default. The drafting prompts read that project; when no project exists the drafting path fails
visibly (`no project configured: add one on /projects`) instead of inventing a product. The seeding
step gives a fresh tenant its first project with the text that used to be hardcoded, so the migration
loses no behaviour.

`POST /api/v1/projects/{id}/match-communities` reads the project's pages through `domain::webfetch`
— `http`/`https` only, public addresses only, no redirects, a timeout and a byte cap — and asks the
configured generative provider to score every community that is **already validated and enabled**.
The ranking lands in `project_communities`. It is advisory by construction: the analysis cannot
enable, disable or validate a community, and it collects nothing.

Opportunity import stays manual: the JSON import and an operator-started Apify run are the only ways
content enters the pipeline.

