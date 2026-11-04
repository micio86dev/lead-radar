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

## Re-scoring after a configuration change

Weights and vertical thresholds are versioned configuration (`lead_score_versions`). Changing them does
not require paying for the same analysis twice:

```bash
make rescore
# or: docker compose run --rm api /usr/local/bin/db rescore
```

It re-reads each active lead's latest successful decision (relevance, evidence sufficiency, ambiguity),
its stored classification, publication time and engagement, recomputes the deterministic score with the
**active** configuration, updates the lead and appends a `lead_scores` row recording the new version.
No provider is called. Output is a JSON summary (`examined`, `updated`, `skipped`, `version`).

Because it reads only stored decisions, a version change can be applied to an existing database at zero
provider cost. Business metrics of a real run are not published in this repository.

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

## Reply queue preparation (scheduled)

The queue refills itself from two schedulers that run the same script, `scripts/prepare-queue.sh`
(`POST /api/v1/reply-console/prepare` with `{"limit": N, "auto": true}`):

| Where | Mechanism | Schedule | Logs |
| --- | --- | --- | --- |
| Local stack | `scheduler` service in `docker-compose.yml` (same image as the cron job, script mounted read-only) | `PREPARE_INTERVAL_SECONDS`, default 3600 | `docker compose logs -f scheduler` |
| Local, native run | launchd agent `dev.leadradar.prepare-queue` (`make cron-install`) | 3600 s | `~/Library/Logs/lead-radar/prepare-queue.log` |
| Railway | service `lead-radar-cron` (cron schedule `0 * * * *`) | hourly | `railway logs -s lead-radar-cron` |

The API caps automatic runs at three drafts and applies a ten-minute per-tenant cooldown, so a shorter
interval or a page refresh cannot multiply spending; the "Generate drafts" button on a card bypasses the
cooldown for a deliberate single batch.

```
make prepare-queue     # one run against the local API
make cron-install      # launchd agent (native runs only)
make cron-status
make cron-run          # trigger one run now
make cron-uninstall    # --purge also removes the stored token
```

macOS gotcha: launchd cannot read this repository when it lives on an external volume (TCC returns
`Operation not permitted`), so `cron-install` writes a small runner under `~/Library/Application Support`
and keeps the API base and token in `~/.config/lead-radar` (0600). Nothing secret goes into the plist.

## Reply pacing

`REPLY_MIN_INTERVAL_MINUTES` (default 10) is the floor shown after a recorded publication; Reddit's own
limit is per account and changes with karma and subreddit, so treat the floor as a reminder, not authority.
The widget can lower or raise the stored wait to what Reddit actually announced
(`POST /api/v1/reply-console/rate-limit`), and the value is visible in `/reply-console` as
`pacing.retry_after_seconds`. There is no automatic retry anywhere in this path.

## Routine checks

1. `GET /ready` returns 200 and `/api/v1/jobs?status=dead_letter` is empty or explained.
2. Provider panel: no unexpected `error` status, last request recent.
3. Apify usage: known actual spend below the daily ceiling; kill switch state as intended.
4. Review queue: nothing stale for too long.
5. `make test` green after any change.
