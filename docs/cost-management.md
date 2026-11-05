# Cost management

Two kinds of spend exist: deterministic local work (free) and provider calls (possibly billable).

## Guard before queueing

`modules::operations::cost_guard` is a pure function used by `sources::guard_apify_run`. A run is queued
only when all of these hold:

| Check | Refusal reason |
|---|---|
| configured source adapter available | `provider_unconfigured` |
| kill switch off | `kill_switch` |
| Actor enabled | `actor_not_enabled` |
| Actor validation recorded | `actor_not_validated` |
| `1 ≤ items_limit ≤ min(actor.max_items_per_run, APIFY_MAX_ITEMS_PER_RUN)` | `limit_invalid` |
| configured estimate ≤ `APIFY_MAX_RUN_COST` | `run_cost_above_limit` |
| total spend < `APIFY_TOTAL_BUDGET` | `budget_exhausted` |
| today's spend < `APIFY_DAILY_BUDGET` | `daily_ceiling_reached` |
| running runs < `APIFY_MAX_CONCURRENT_RUNS` | `concurrency_limit` |

Defaults are deliberately conservative: 25 EUR promotional budget, 2 EUR per day, 0.50 EUR per run,
50 items per run, 2 concurrent runs, kill switch off. `PATCH /api/v1/settings` can lower these values
(invalid or widening overrides are ignored), and `db settings` prints the stored values.

The override is what the guard applies, so it is also what every reporting surface shows:
`GET /api/v1/providers/apify/usage` and the dashboard's `apify` block read the same effective budgets as
`guard_apify_run`. A panel that showed the environment defaults instead would advertise a ceiling the
guard does not honour — and, worse, a kill switch that is engaged while the page says it is off.

## Currency honesty

The promotional budget is EUR; Apify reports charges in USD (`usageTotalUsd`). The system never applies
an invented exchange rate: `known_actual_usd` and the EUR ceilings are displayed side by side, and
`remaining_known_eur` is `null` once USD spend exists. Where spend cannot be bounded, the per-run ceiling
and the item limit keep the exposure small.

## AI spend

- Deduplicate and keyword-filter before any AI call; irrelevant posts never reach a provider.
- The decision provider reads the state once with up to 13 questions in one request.
- Qwen runs only for selected opportunities, on explicit human action.
- Costs are recorded per provider with `actual`, `estimate` or `unknown`; unknown is `null`/counted and
  never displayed as `0`.
- A billable run is never silently retried: retries reuse the decision run id as `Idempotency-Key`, and
  non-retryable failures become dead letters.

## Dashboard visibility

`GET /api/v1/dashboard` and `GET /api/v1/providers/apify/usage` show configured ceilings, known actual
spend, estimates, remaining known budget, runs, results, errors and the cost source
(`actual`/`estimate`/`unknown`). `GET /api/v1/providers/usage` returns 30-day per-provider requests,
tokens, actual and estimated costs and the number of unknown-cost requests.

## Operational guidance

- Start with one validated Actor and a small `items_limit`; confirm the first real cost in the Apify
  console before raising the daily ceiling.
- Keep `APIFY_KILL_SWITCH=true` outside working sessions.
- Treat the exploratory credit as a one-off budget, not recurring funding.
