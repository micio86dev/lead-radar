# Laya integration

Verified against the Laya Studio OpenAPI document (`https://laya.studio/v1/openapi`), which states that
the decision endpoint is wire-compatible with the TypeSafe/Jev protocol.

- Base URL: `https://api.laya.studio` (`LAYA_BASE_URL`)
- Endpoint: `POST /v1/systemone`
- Auth: its own key (`LAYA_API_KEY`); the Jev key is never reused
- Model: `LAYA_MODEL` accepts only the documented values `english`, `multilingual`,
  `typed-decisions`; empty means "route automatically". **Jev model ids are rejected at startup**,
  because the provider ignores unknown ids and silently falling back would make benchmarks meaningless.

## Role: benchmark only

Laya is implemented behind the same `DecisionProvider` trait, disabled by default (`LAYA_ENABLED=false`),
and never used for production decisions. `Providers::from_config` builds it only when enabled; the
benchmark job addresses it as `"laya"`.

## Benchmark path

`POST /api/v1/providers/benchmark` with `{ "dataset": "seed", "providers": ["jev", "laya"] }` enqueues a
`benchmark_execution` job. The job evaluates the same `benchmark_items` rows (split `evaluation` only)
with each provider, records `provider_usage`, and stores per-provider predictions plus metrics
(precision, recall, F1, accuracy, FPR, FNR, confusion matrix, per-language metrics, mean latency and
`cost_per_1000_usd`). Because no unit price is configured, the cost per 1000 is stored as `null` with
`unknown_costs` set to the number of evaluated items; that is reported as unknown, not as zero.

Results are stored per provider with the adapter that answered, so Jev and Laya stay independently
auditable. `docs/benchmarks` do not switch the production provider: a provider change is a configuration
decision made after enough labeled data exists.

## Model versioning

The stored result keeps `model` and `model_version` (when the provider reports one). Benchmark
comparisons should use pinned model ids; a rolling alias makes comparisons non-reproducible.

## Adapter reuse

`JevCompatibleProvider` is shared between Jev and Laya: request building, strict response parsing, error
mapping, idempotency header and limits are identical, which is exactly what "wire-compatible" claims.
The only differences are the endpoint, the key and the optional model.
