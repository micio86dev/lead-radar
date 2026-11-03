# Lead Radar HTTP API (v1)

This document is the implementation contract between `lead-radar-backend` and
`lead-radar-frontend`. It describes the API as implemented; anything not listed here does not exist.

- Base URL: `${PUBLIC_API_BASE_URL}` (default `http://localhost:8080`).
- All application endpoints are versioned under `/api/v1`. `GET /health` and `GET /ready` are
  unversioned so containers can probe them.
- Requests and responses are `application/json`.
- Authentication: `Authorization: Bearer <token>`. The token is resolved server-side to a user and a
  tenant; a tenant identifier is **never** accepted from a body, path or query string.
  In `APP_ENV=development` the API accepts `DEV_API_TOKEN` (default `dev-local-token`).
  In production, tokens must exist in the database (hashed) and a missing or unknown token is `401`.
- Every tenant-owned row is filtered by the authenticated tenant. A resource of another tenant
  answers `404`, never `403` (no existence leak).

## Error format

```json
{ "error": { "code": "validation_failed", "message": "Request body is invalid",
             "details": [ { "field": "posts[0].content", "message": "must not be empty" } ] } }
```

| HTTP | `code` | Meaning |
|---|---|---|
| 400 | `bad_request` | Malformed JSON, unknown query value |
| 401 | `unauthorized` | Missing/invalid token |
| 403 | `forbidden` | Authenticated but not permitted (e.g. reviewer role required) |
| 404 | `not_found` | Unknown or other-tenant resource |
| 409 | `conflict` | Illegal state transition (e.g. publish a non-approved comment) |
| 409 | `cost_guard_rejected` | Billable action refused by the spend guard (`details.reason`) |
| 422 | `validation_failed` | Field-level validation errors |
| 429 | `rate_limited` | Provider or local rate limit |
| 502 | `provider_error` | Upstream provider failed |
| 503 | `not_ready` | Database unavailable or provider unconfigured where required |

## Pagination, filtering, sorting

List endpoints accept `page` (1-based, default `1`) and `per_page` (default `25`, max `100`) and
return:

```json
{ "items": [ ], "page": 1, "per_page": 25, "total": 0 }
```

Unknown filter values answer `400 bad_request`. Timestamps are RFC 3339 UTC strings.
Money is expressed in EUR for Apify and USD for AI providers, as decimal numbers, and **unknown cost
is `null`, never `0`**. Probability/confidence values are `0..1` decimals.

## Enumerations

- `vertical`: `hr_recruiting`, `international_meetings`, `conferences_webinars`,
  `customer_support`, `tourism_hospitality`, `other`.
- `intent`: `explicit_solution_request`, `active_problem`, `latent_problem`, `product_comparison`,
  `general_discussion`, `irrelevant`.
- `customer_type`: `b2b`, `b2c`, `unknown`.
- `buying_intent`: `none`, `weak`, `moderate`, `strong`, `explicit`.
- `business_potential`: `low`, `moderate`, `high`, `very_high`.
- `product_fit`: `poor`, `partial`, `good`, `excellent`.
- `score_category`: `hot`, `warm`, `potential`, `low`.
- `qualification_status`: `pending`, `qualified`, `needs_review`, `rejected`.
- `review_status`: `none`, `pending`, `in_review`, `resolved`.
- `comment_status`: `draft`, `pending_review`, `needs_edit`, `approved`, `rejected`,
  `published_manually`.
- `comment_variant`: `helpful`, `soft_pitch`, `direct_pitch`.
- `validation_status`: `pending`, `validated`, `rejected`.
- `job_status`: `queued`, `running`, `succeeded`, `failed`, `dead_letter`, `cancelled`.
- `provider_status`: `ok`, `error`, `unconfigured`, `disabled`.

## System

### `GET /health`

`200` — `{ "status": "ok", "version": "0.1.0", "uptime_seconds": 12 }`

### `GET /ready`

`200` — `{ "status": "ready", "database": "ok" }`; `503` with the error format otherwise.

### `GET /api/v1/dashboard`

```json
{
  "totals": { "opportunities": 42, "new_opportunities": 7, "hot": 3, "warm": 9, "potential": 14,
              "low": 16 },
  "by_vertical": [ { "vertical": "hr_recruiting", "count": 10 } ],
  "by_intent": [ { "intent": "active_problem", "count": 12 } ],
  "recent_opportunities": [ OpportunityListItem ],
  "ai_decisions": { "total": 40, "providers": [ { "provider": "jev", "count": 40,
                     "avg_confidence": 0.82 } ] },
  "review_queue": { "pending_review": 4, "needs_edit": 1, "approved": 2 },
  "providers": [ ProviderStatus ],
  "apify": { "budget_eur": 25.0, "known_actual_eur": 0.42, "estimated_eur": 0.5,
             "remaining_known_eur": 24.58, "runs": 3, "results": 120, "errors": 1,
             "kill_switch": false },
  "job_failures": { "failed": 1, "dead_letter": 0 },
  "costs": [ ProviderCost ]
}
```

## Opportunities

### `GET /api/v1/opportunities`

Query: `vertical`, `score_category`, `score_min`, `score_max`, `intent`, `language`, `source_id`,
`community`, `published_after`, `published_before`, `review_status`, `customer_type`,
`buying_intent`, `q` (substring of title/content), `sort` (`score`|`recency`|`buying_intent`|
`confidence`, default `score`), `order` (`desc`|`asc`, default `desc`), `page`, `per_page`.

`OpportunityListItem`:

```json
{ "id": "uuid", "title": "...", "snippet": "first 280 chars", "language": "en",
  "source_id": "uuid", "source_name": "manual-import", "community": "recruiting",
  "url": "https://...", "published_at": "2024-05-01T10:00:00Z",
  "discovered_at": "2024-05-01T10:01:00Z", "vertical_primary": "hr_recruiting",
  "vertical_secondary": ["international_meetings"], "intent": "active_problem",
  "customer_type": "b2b", "buying_intent": "moderate", "business_potential": "high",
  "product_fit": "good", "score": 74, "score_category": "warm",
  "qualification_status": "qualified", "review_status": "pending", "confidence": 0.81,
  "evidence_count": 2, "comment_count": 3, "created_at": "2024-05-01T10:02:00Z" }
```

### `GET /api/v1/opportunities/:id`

`OpportunityDetail` = every list field plus:

```json
{
  "content": "full original text", "author": "handle or null",
  "engagement": { "comments": 4, "upvotes": 12, "shares": 0 },
  "evidence": [ { "excerpt": "...", "start_offset": 0, "end_offset": 42 } ],
  "score_breakdown": {
    "version": 1, "score": 74, "category": "warm",
    "components": [ { "dimension": "problem_relevance", "weight": 25, "raw": 0.8,
                      "normalized": 0.8, "contribution": 20.0 } ],
    "inputs": { "relevance_probability": 0.8, "buying_intent": "moderate",
                "business_potential": "high", "product_fit": "good",
                "recency_hours": 30, "engagement_normalized": 0.4 },
    "created_at": "2024-05-01T10:03:00Z" },
  "decision": { "provider": "jev", "model": "jev-1.13", "model_version": "jev-1.13-20260917",
                "provider_request_id": "dec_...", "confidence": 0.81, "latency_ms": 940,
                "input_tokens": 503, "output_tokens": 70, "created_at": "...",
                "answers": [ { "question": "relevance", "type": "noul", "value": 0.82,
                               "label": null, "probabilities": null, "confidence": null } ] },
  "analyses": [ { "kind": "generative_analysis", "provider": "qwen", "model": "...",
                  "summary": "...", "created_at": "..." } ],
  "comments": [ CommentSummary ],
  "engagements": [ Engagement ]
}
```

`decision` is `null` before the first decision; `score_breakdown` is `null` before scoring.

### `POST /api/v1/opportunities/:id/analyze`

Queues a fresh decision + scoring pass. `202` — `{ "job_id": "uuid", "lead_id": "uuid" }`.

### `POST /api/v1/opportunities/:id/generate-comments`

Queues comment generation. `202` — `{ "job_id": "uuid" }`. Refused with `503 not_ready` when the
generative provider is unconfigured.

### `DELETE /api/v1/opportunities/:id`

Data-removal path (retention/erasure). Deletes the post content, its analyses and unreviewed
comments of that opportunity, keeps an audit record. `204`.

## Comments

### `GET /api/v1/comments`

Query: `status`, `variant`, `lead_id`, `page`, `per_page`.

`CommentSummary` — `{ "id", "lead_id", "lead_title", "variant", "status", "language", "body",
"version", "created_at", "updated_at", "published_at" }`.

### `GET /api/v1/comments/:id`

`CommentDetail` = summary + `lead: {id,title,url,language}` + `versions: [{version, body,
created_at, actor}]` + `review_events: [{event, actor, note, created_at}]`.

### `PATCH /api/v1/comments/:id`

Body: `{ "body": "new text", "status": "needs_edit" }` (any subset). A body change creates a new
version. Allowed status targets: `draft`, `pending_review`, `needs_edit`. `409` for `approved`,
`rejected`, `published_manually` — those go through their own endpoints. Returns `CommentDetail`.

### `POST /api/v1/comments/:id/approve`

Body `{ "note": "optional" }`. Only from `pending_review`/`needs_edit`/`draft` → `approved`.
Records a review event. `409` otherwise. Returns `CommentDetail`.

### `POST /api/v1/comments/:id/reject`

Body `{ "note": "optional" }`. → `rejected`. Returns `CommentDetail`.

### `POST /api/v1/comments/:id/record-publication`

Body `{ "published_at": "2024-05-02T09:00:00Z", "note": "posted manually" }`. Only from `approved`
→ `published_manually`. This endpoint records a human action; it never contacts a third party.
Returns `CommentDetail`.

## Engagements

### `GET /api/v1/engagements`

Query: `lead_id`, `kind`, `page`, `per_page`.

### `POST /api/v1/engagements`

Body: `{ "lead_id": "uuid", "comment_id": "uuid|null", "kind": "reply|dm|meeting|interest|lost|other",
"note": "optional", "occurred_at": "optional RFC3339" }` → `201` with `Engagement`.

## Search profiles

- `GET /api/v1/search-profiles` → paginated `SearchProfile`
  `{ id, name, vertical, enabled, keywords: [string], negative_keywords: [string], created_at,
  updated_at }`.
- `POST /api/v1/search-profiles` — `{ name, vertical, enabled?, keywords?, negative_keywords? }` →
  `201`.
- `GET /api/v1/search-profiles/:id`
- `PATCH /api/v1/search-profiles/:id` — any subset of `name`, `enabled`, `keywords`,
  `negative_keywords` (lists replace).
- `DELETE /api/v1/search-profiles/:id` → `204`.

## Communities

- `GET /api/v1/communities` — query `vertical`, `validation_status`; `Community`
  `{ id, name, vertical, validation_status, enabled, notes, last_checked_at, created_at }`.
- `PATCH /api/v1/communities/:id` — `{ enabled?, notes? }`. Enabling a community whose
  `validation_status != "validated"` answers `409 conflict` with a `message` starting
  `community_not_validated:`.
- `POST /api/v1/communities/:id/validate` — `{ "outcome": "validated"|"rejected",
  "evidence": "what was verified and where", "notes?": "..." }`. Requires a non-empty `evidence`
  (422 otherwise). Records an audit log entry and returns the community.

## Sources

- `GET /api/v1/sources` → paginated `Source` `{ id, name, provider, source_type, enabled,
  validation_status, notes, config: object, last_run_at, created_at }`.
- `POST /api/v1/sources` — `{ name, provider, source_type, config: object }` → `201`. `provider` is
  one of `apify`, `manual_import`, `official_api`, `licensed_feed`; `source_type` is one of
  `community_feed`, `manual_json`, `webhook`.
- `PATCH /api/v1/sources/:id` — `{ name?, enabled?, config? }`.
- `POST /api/v1/sources/:id/test` — `{ "status": "ok"|"error"|"unconfigured", "message": "...",
  "latency_ms": null }`.

## Apify

- `GET /api/v1/providers/apify/actors` → paginated `Actor` `{ id, provider, actor_id, name,
  description, source_type, enabled, validation_status, max_items_per_run, cost_per_run_estimate,
  max_total_charge_usd, input_template: object, last_success_at, created_at }`.
- `POST /api/v1/providers/apify/actors` — `{ actor_id, name, description?, source_type,
  input_template?, max_items_per_run?, max_run_cost_eur?, max_total_charge_usd? }` → `201`.
  `max_total_charge_usd` is the provider-side per-run cap forwarded as Apify `maxTotalChargeUsd`
  (defaults to `APIFY_MAX_TOTAL_CHARGE_USD`). Never guesses an Actor ID:
  it is stored exactly as supplied. New Actors are stored `enabled=false`,
  `validation_status="pending"`.
- `PATCH /api/v1/providers/apify/actors/:id` — `{ validation_status?: "pending"|"validated"|
  "rejected", enabled?: bool, description?, max_items_per_run?, input_template? }`. Enabling an Actor
  whose effective `validation_status` is not `validated` answers `409 conflict` with
  `message` starting `actor_not_validated:`. Returns the Actor.
- `POST /api/v1/providers/apify/runs` — `{ "actor_registry_id": "uuid", "input_override": {},
  "items_limit": 25 }` → `202 { "job_id", "run_id", "status": "queued" }` or
  `409 cost_guard_rejected` with `details.reason` in `kill_switch`, `budget_exhausted`,
  `daily_ceiling_reached`, `concurrency_limit`, `actor_not_enabled`, `actor_not_validated`,
  `run_cost_above_limit`, `provider_unconfigured`.
- `GET /api/v1/providers/apify/runs` — query `status`, `actor_registry_id`; `ApifyRun`
  `{ id, actor_registry_id, actor_name, status, items_count, dataset_id, cost_estimate_usd,
  cost_actual_usd, started_at, finished_at, error, job_id, created_at }`. Apify reports spend in USD;
  the configured ceilings are EUR and are never converted.
- `GET /api/v1/providers/apify/runs/:id` — `ApifyRun` + `{ "job_id": "uuid|null" }`.
- `POST /api/v1/providers/apify/runs/:id/cancel` → `202 { "status": "aborted" }`; a finished run
  answers `409 conflict`.
- `GET /api/v1/providers/apify/usage` → `{ budget_eur, daily_budget_eur, max_run_cost_eur,
  max_concurrent_runs, max_items_per_run, known_actual_usd, estimated_usd, remaining_known_eur,
  runs_total, runs_running, results_total, errors_total, kill_switch,
  cost_source: "actual"|"estimate"|"unknown", currency_note }`.

## AI providers

`stale` is true when the last recorded outcome is a failure older than 24 hours: history, not a current
outage.

- `GET /api/v1/providers` → `ProviderStatus[]` (not paginated)
  `{ provider: "jev"|"laya"|"qwen"|"apify", kind: "decision"|"generative"|"source", configured,
  enabled, model, status, last_request_at, last_latency_ms, last_error, last_success_at,
  last_error_at, stale,
  usage: { requests, input_tokens, output_tokens } }`.
- `POST /api/v1/providers/:provider/test` → `{ provider, status, latency_ms, message }`.
  `:provider` ∈ `jev|laya|qwen|apify`. This performs a real, possibly billable probe; dashboards never
  call it, they read recorded usage instead.
- `GET /api/v1/providers/usage` → `ProviderCost[]`
  `{ provider, requests, input_tokens, output_tokens, actual_cost_usd, estimated_cost_usd,
  unknown_cost_requests, currency: "USD", period: { from, to } }`.
- `GET /api/v1/providers/decisions` — query `provider`, `page`, `per_page`; `DecisionSummary`
  `{ id, lead_id, provider, model, model_version, confidence, intent, vertical, latency_ms,
  created_at }`.
- `POST /api/v1/providers/benchmark` — `{ dataset: "seed"|"<dataset_id>", providers: ["jev","laya"] }`
  → `202 { job_id, benchmark_run_id }`. `jev` addresses the production decision role and `laya` the
  benchmark role; each stored result names the adapter that actually answered (for example `mock`
  when `DECISION_PROVIDER=mock`).
- `GET /api/v1/providers/benchmark` → paginated `BenchmarkRunSummary`
  `{ id, dataset, status, providers, item_count, error, created_at, finished_at }`.
- `GET /api/v1/providers/benchmark/:id` → `BenchmarkRunDetail` = summary + `results:
  [{ provider, model, model_version, metrics: { precision, recall, f1, accuracy,
  false_positive_rate, false_negative_rate, confusion_matrix: { tp, fp, tn, fn },
  per_language: [ { language, precision, recall, f1, count } ] }, latency_ms_avg,
  cost_per_1000_usd, unknown_costs, created_at }]`.

## Import

### `POST /api/v1/import/json`

Body:

```json
{ "source_name": "manual-import",
  "posts": [ { "external_id": "optional-stable-id", "title": "optional", "content": "required",
               "url": "https://...", "author": "handle", "community": "recruiting",
               "language": "en", "published_at": "2024-05-01T10:00:00Z",
               "engagement": { "comments": 4, "upvotes": 12, "shares": 0 } } ] }
```

`202` — `{ "ingestion_run_id": "uuid", "imported": 10, "duplicates": 2, "rejected": 1,
"rejected_reasons": ["content must not be empty"], "job_ids": ["uuid"] }`. Duplicates are detected by `external_id` and by `content_hash`; re-importing
the same payload never creates a second active lead.

## Settings and operations

- `GET /api/v1/settings` → `{ tenant: { id, name }, operational: { worker_concurrency,
  ai_concurrency, job_max_attempts, retention_days }, budgets: { apify_total_eur,
  apify_daily_eur, apify_max_run_eur, apify_max_items_per_run, apify_max_concurrent_runs,
  kill_switch }, providers: ProviderStatus[] }`.
- `PATCH /api/v1/settings` — subset of `{ retention_days, budgets: { apify_total_budget_eur,
  apify_daily_budget_eur, apify_max_run_cost_eur, apify_max_items_per_run,
  apify_max_concurrent_runs, kill_switch }, providers: { jev_enabled, qwen_enabled } }`. Budget
  overrides are validated and can only tighten the environment ceilings; the spend guard reads them.
  `jev_enabled=false` or `qwen_enabled=false` makes the decision or generative call fail loudly instead
  of silently continuing.
- `GET /api/v1/jobs` — query `status`, `kind`; `Job` `{ id, kind, status, attempts, max_attempts,
  run_at, last_error, created_at, updated_at }`.
- `POST /api/v1/jobs/:id/retry` — `202 { "job_id": "uuid", "status": "queued" }` for `failed` and
  `dead_letter` jobs only.

## OpenAPI

`GET /api/v1/openapi.json` returns the generated OpenAPI 3.1 document for every endpoint above.
