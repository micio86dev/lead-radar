# Operations

## Process layout

| Binary | Purpose |
|---|---|
| `api` | Axum HTTP server on `APP_HOST:APP_PORT`; runs migrations at startup |
| `worker` | durable job loop with bounded concurrency; runs migrations at startup |
| `db` | `migrate`, `seed`, `purge [days]`, `reset --confirm`, `token <plaintext>`, `settings` |
| `healthcheck` | container probe for `GET /health` |

API and worker share the SQLite file (WAL) and must run on the same host/volume. Only one process
writes at a time by design; the writer pool has a single connection.

## Health

- `GET /health` — process alive, version, uptime.
- `GET /ready` — database reachable; `503` otherwise.
- Container healthchecks use both (`docker-compose.yml`).

## Jobs

`POST /api/v1/jobs/:id/retry` requeues a `failed` or `dead_letter` job. `GET /api/v1/jobs?status=…`
lists them. Every attempt is stored in `job_attempts` with duration and error. A crashed worker's job
has an expired lease and is reclaimed by the next worker (`attempts` increments).

Job kinds: `discovery`, `actor_run`, `dataset_ingestion`, `normalization`, `deduplication`,
`decision_evaluation`, `generative_analysis`, `comment_generation`, `benchmark_execution`.

## Graceful shutdown

`worker` handles `SIGINT`: it stops claiming, waits up to 30 s for in-flight jobs, then closes the
database. A job that does not finish before the lease expires is reclaimed later; the pipeline is
idempotent by constraint, so a reclaimed job cannot duplicate a post or a lead.

## Logs

Structured `tracing` logs to stdout, filter from `LOG_LEVEL`/`RUST_LOG`. Provider errors are logged with
their type and status, never with credentials or full upstream bodies.

## Backup and recovery

- Backup: stop the worker (or accept a WAL copy), run
  `sqlite3 data/lead-radar.db ".backup 'lead-radar-$(date +%F).db'"`.
- Restore: stop the stack, replace the file, restart. Migrations then run forward only.
- `make reset-db` removes the volume; `db reset --confirm` clears rows in an existing database.

## Retention

`RETENTION_DAYS` (default 180) and the `retention_days` setting define the window. `db purge` overwrites
content older than the window and marks posts deleted. `DELETE /api/v1/opportunities/:id` handles
individual removal requests and writes an audit entry.

## Routine checks

1. `GET /ready` returns 200 and `/api/v1/jobs?status=dead_letter` is empty or explained.
2. Provider panel: no unexpected `error` status, last request recent.
3. Apify usage: known actual spend below the daily ceiling; kill switch state as intended.
4. Review queue: nothing stale for too long.
5. `make test` green after any change.
