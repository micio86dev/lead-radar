# Database

SQLite in WAL mode with foreign keys enabled, a 10 s busy timeout and one writer connection. All
schema changes are versioned SQLx migrations in `lead-radar-backend/migrations/`; they are embedded in
the binary and applied by `db migrate` (also run by both binaries at startup).

## Migrations

| File | Contents |
|---|---|
| `0001_identity.sql` | `tenants`, `users`, `tenant_users`, `api_tokens`, `app_settings` |
| `0002_sources.sql` | `source_providers`, `sources`, `actor_registry`, `communities`, `search_profiles`, `keywords` |
| `0003_discovery.sql` | `ingestion_runs`, `discovered_posts`, `post_sources`, `ingestion_items` |
| `0004_intelligence.sql` | `decision_runs`, `decision_answers`, `ai_analyses`, `benchmark_items`, `benchmark_runs`, `benchmark_results`, `provider_configs` |
| `0005_commercial.sql` | `lead_score_versions`, `leads`, `lead_scores` |
| `0006_comments_engagement.sql` | `generated_comments`, `comment_versions`, `review_events`, `engagements` |
| `0007_operations.sql` | `jobs`, `job_attempts`, `provider_usage`, `provider_costs`, `audit_logs`, `apify_runs` |

## Design decisions

- **Tenancy everywhere.** Tenant-owned tables carry `tenant_id` with a foreign key to `tenants`. The
  API derives it from the token, never from input.
- **Deduplication in the schema.** `discovered_posts` has `UNIQUE(tenant_id, content_hash)` and a
  partial unique index on `(tenant_id, source_id, external_id)`; `leads` has `UNIQUE(tenant_id,
  post_id)`, so re-analysis updates the same lead instead of creating a duplicate.
- **Analysis history.** `decision_runs` + `decision_answers` keep every evaluation; `lead_scores`
  keeps each computed score with its version, components and inputs, so a score can be explained later.
- **Versioned scoring.** `lead_score_versions` stores weights, bands and vertical thresholds; one row
  per tenant is `active` (enforced by a partial unique index).
- **Money.** `provider_costs` separates `actual` and `estimate` rows, keeps the provider currency in
  its own column and marks unknown amounts with `unknown = 1` and a zero amount. `apify_runs` stores
  provider-reported cost in USD.
- **Jobs.** `jobs.idempotency_key` is unique, so scheduling the same unit twice is a no-op.
  `job_attempts` records every attempt. `lease_owner`/`lease_expires_at` make an interrupted job
  reclaimable.
- **Comments.** `generated_comments` holds the current body and status; `comment_versions` and
  `review_events` are append-only history.
- **Retention.** `discovered_posts.deleted_at` plus content overwrite implements removal; `db purge`
  applies the configured window to older rows.

## Indexes

`tenant_id` on every tenant-owned table; publication timestamp and community on `discovered_posts`;
score, qualification status, vertical and publication time on `leads`; status on `generated_comments`;
`(status, run_at)` on `jobs`; `(tenant_id, created_at)` on `audit_logs` and `provider_usage`.

## Moving to PostgreSQL

The domain layer never sees SQL. Repositories use plain SQL with bound parameters and no SQLite-only
syntax except `INSERT … ON CONFLICT DO NOTHING` (also supported by PostgreSQL). Migrating means
adapting the migration files, the pool setup and the timestamp binding; module interfaces and domain
rules stay unchanged.

## Backup and reset

- Backup: stop the worker, copy the SQLite file (WAL checkpoint happens on clean shutdown), or use
  `sqlite3 data/lead-radar.db ".backup backup.db"`.
- `make reset-db` deletes the Docker volume and is destructive by design.
- `db reset --confirm` clears rows inside an existing database; it refuses without `--confirm`.
