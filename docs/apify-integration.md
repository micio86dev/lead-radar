# Apify integration

Implementation: `lead-radar-backend/src/providers/apify.rs` over the documented Apify REST API
(`https://docs.apify.com/api`). The token is sent only in an `Authorization: Bearer` header.

## Calls used

| Purpose | Request |
|---|---|
| Start a run | `POST {APIFY_BASE_URL}/v2/acts/{actor_id}/runs` with `{ input, maxItems }` |
| Run status | `GET {APIFY_BASE_URL}/v2/actor-runs/{run_id}` |
| Dataset items | `GET {APIFY_BASE_URL}/v2/datasets/{dataset_id}/items?format=json&clean=true&offset=…&limit=…` |
| Cancel | `POST {APIFY_BASE_URL}/v2/actor-runs/{run_id}/abort` |
| Health | `GET {APIFY_BASE_URL}/v2/users/me` |

Run status is mapped to `queued` (`READY`), `running` (`RUNNING`/`ABORTING`/`TIMING-OUT`), `succeeded`,
`failed`, `aborted`, `timed_out`. Provider-reported `usageTotalUsd` is stored as the actual run cost in
USD.

## Asynchronous lifecycle

`POST /api/v1/providers/apify/runs` (or a `discovery` job) creates an `apify_runs` row and an
`actor_run` job. The worker starts the run once, then requeues itself with the configured poll interval
until the run is terminal; on success it enqueues `dataset_ingestion`, which pages through the dataset
(100 items per page), maps each item with the documented generic mapping and imports it through the same
deduplicating path as manual JSON. A page that is full requeues the job with the next offset. No request
blocks on the Actor and no transaction is held.

## Actor registry

`actor_registry` rows are operator configuration: `actor_id`, name, source type, input template, max
items per run and an optional cost estimate. New Actors are stored `enabled = false` and
`validation_status = "pending"`. `PATCH /api/v1/providers/apify/actors/:id` records validation and
enables the Actor; enabling an unvalidated Actor is refused.

**No Actor id, input schema or price is invented by the codebase.** The seed creates no Actor: the
operator registers the one they verified.

## Generic dataset mapping

`map_dataset_item` reads only documented aliases: `content|text|body|selftext|description` for the
body, `title|headline`, `url|permalink|link`, `author|username|user`, `community|subreddit|forum|
channel`, `language|lang`, `published_at|createdAt|created_at|date|timestamp`, and engagement from
`engagement.*` or `num_comments`/`score`. Items without a body are skipped. Actors that need a different
shape require a dedicated adapter; do not stretch the mapping.

## Targeted sweep script

`scripts/apify-community-sweep.py` drives the whole loop over approved communities: one run per
community with `withinCommunity` and quoted phrases per vertical, polling until terminal, then waiting
for ingestion and decisions and printing the scoreboard. `--only`/`--skip` select communities, `--items`
bounds the dataset, and every run carries the actor's charge cap. The bearer token comes from `.env` and
is never printed.

```bash
./scripts/apify-community-sweep.py --only CrossLanguageCalls,eventprofs --extra-terms '"Wordly"'
```

## Sources versus Actors

Two records exist and they do different jobs:

- `actor_registry` drives collection. A run starts from an Actor that is enabled **and** validated;
  its `input_template` is the documented input for that Actor.
- `sources` records provenance and validation. Dataset items are attributed to the `apify-default`
  source, and a source must be validated (with evidence) before it can be enabled. Enabling a source
  never starts collection.

## Re-processing a collected dataset

`POST /api/v1/providers/apify/runs/:id/reingest` re-queues ingestion for a run that already produced a
dataset (the dashboard shows a **Re-ingest** button). Apify is not called and nothing is billed: the
stored dataset is read again, duplicates backfill missing metadata (community, URL, author, engagement),
and posts are re-evaluated against the current keyword configuration. Posts already decided keep their
decision (the decision job is idempotent per post content), so only newly matching posts cost a decision.

## URL of an ingested item

The generic mapping resolves relative permalinks (`/r/…`) against `https://www.reddit.com` when the item
also identifies a subreddit/community, keeps absolute URLs untouched, and stores nothing rather than
guessing a host for an unknown provider.

## Spending controls

Every run passes `sources::guard_apify_run` before it is queued:

1. the configured source adapter is available (credentials when `SOURCE_PROVIDER=apify`);
2. the kill switch is off;
3. the Actor is enabled **and** validated;
4. `items_limit` is within `1..=min(actor.max_items_per_run, APIFY_MAX_ITEMS_PER_RUN)`;
5. the Actor's configured estimate is not above `APIFY_MAX_RUN_COST`;
6. total spend is below `APIFY_TOTAL_BUDGET` and today's spend below `APIFY_DAILY_BUDGET`;
7. fewer than `APIFY_MAX_CONCURRENT_RUNS` runs are queued or running.

A second, separate ceiling bounds provider-reported USD spend per day (`APIFY_DAILY_CHARGE_USD`, default
1.00 USD). The EUR ceilings and the Apify USD ledger are never converted into each other: the guard
refuses a run when `today's USD spend >= APIFY_DAILY_CHARGE_USD`, independently of the EUR budget.

Every run also carries `maxTotalChargeUsd` (the Actor's `max_total_charge_usd`, default
`APIFY_MAX_TOTAL_CHARGE_USD`), a cap Apify enforces itself: a pay-per-event Actor cannot bill beyond it.
That cap is in USD and is never converted from the EUR ceilings.

Refusals answer `409 cost_guard_rejected` with `details.reason` in `kill_switch`, `budget_exhausted`,
`daily_ceiling_reached`, `concurrency_limit`, `actor_not_enabled`, `actor_not_validated`,
`run_cost_above_limit`, `limit_invalid`, `provider_unconfigured`.

Currencies are never converted: ceilings are EUR (the promotional budget), Apify reports USD, and both
are shown separately. When spend in USD exists, `remaining_known_eur` is `null` instead of a fabricated
conversion.

## What is not implemented

- Webhook-based completion (the worker polls, which survives restarts).
- Provider usage/billing endpoints beyond what a run reports; balances are never displayed as facts.
- Automatic Actor validation: it is a human decision recorded through the API.
