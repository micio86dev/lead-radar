# Providers

Every external system sits behind one of three traits in `lead-radar-backend/src/providers/mod.rs`:

```rust
trait DecisionProvider  { metadata(); health_check(); evaluate(&DecisionRequest) -> DecisionResult }
trait GenerativeProvider { metadata(); health_check(); generate_json(system, user, schema_hint) }
trait SourceProvider     { metadata(); health_check(); start_run(); get_run(); fetch_items(); cancel_run() }
```

| Role | Production adapter | Offline adapter | Selected by |
|---|---|---|---|
| Structured decisions | `remote::JevProvider` | `mock::MockDecisionProvider` | `DECISION_PROVIDER=jev|mock` |
| Benchmark decisions | `remote::LayaProvider` | — | `LAYA_ENABLED` |
| Generative | `qwen::QwenProvider` | `mock::MockGenerativeProvider` | `GENERATIVE_PROVIDER=qwen|mock` |
| Data source | `apify::ApifyProvider` | `mock::MockSourceProvider` | `SOURCE_PROVIDER=apify|mock` |

Mock providers are explicit opt-ins and are rejected in `APP_ENV=production`. There is no silent
fallback: an unconfigured real adapter reports `unconfigured` and its job fails visibly.

## Provider errors

`ProviderError` distinguishes `Unconfigured`, `Disabled`, `InvalidRequest`, `Unauthorized`,
`RateLimited { retry_after_seconds }`, `Upstream { status, message }`, `Unavailable`, `InvalidResponse`
and `Transport`. `is_retryable()` is true only for rate limits, unavailability and transport errors
(and 5xx upstream responses); the worker turns non-retryable failures into dead letters instead of
retrying a possibly billable call.

## Usage recording

Every call records a `provider_usage` row (provider, operation, request id, tokens, latency, status,
error). Costs are recorded separately in `provider_costs` with their currency and an `unknown` flag;
when a provider reports no unit price the amount stays unknown rather than guessed.

## Status

`GET /api/v1/providers` derives status from configuration plus recorded usage: `unconfigured`,
`disabled`, `ok` or `error`. `POST /api/v1/providers/:provider/test` performs a real probe (Jev/Laya: a
one-question decision; Qwen: a minimal completion; Apify: `GET /v2/users/me`). Probes may be billed;
never call them from a page render.

## Adding a provider

1. Implement the trait in `src/providers/<name>.rs`; keep its payload types private.
2. Map its errors onto `ProviderError`, including `retry_after_seconds` when documented.
3. Add configuration (base URL, key, model, timeout) and validation in `src/config.rs`.
4. Wire it in `Providers::from_config`.
5. Add wiremock contract tests: success, malformed body, missing field, 401, 429 with `Retry-After`,
   5xx and an unconfigured instance that must not perform a call.
6. Document the real contract in `docs/`.
