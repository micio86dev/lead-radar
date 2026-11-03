# Jev integration

Verified against `https://jev-ai.org/docs/decisions/` and `https://jev-ai.org/docs/question-types/`.
Implementation: `lead-radar-backend/src/providers/remote.rs` (`JevCompatibleProvider`).

## Deployments

Two documented deployments speak this protocol and use different key families. The adapter only needs
the base URL, the path and the model, so both are configuration:

| Deployment | Key prefix | `JEV_BASE_URL` | `JEV_API_PATH` | Models |
|---|---|---|---|---|
| jev-ai.org (Jev site) | `sk-glm5-` | `https://jev-ai.org` | `/api/v1/systemone/` | `jev-1.13` |
| api.typesafe.ai (TypeSafe console) | `apikey_` | `https://api.typesafe.ai` | `/v1/systemone` | `jev-latest` (resolves to `jev-1.14.0`), `jev-1.14.0` |

A key from one deployment is rejected by the other (`401 invalid_api_key`, `reason: unknown_key`), and
model ids are not interchangeable: `jev-1.13` answers `400 Unknown model` on api.typesafe.ai. Pin a
resolved snapshot (`jev-1.14.0`) for reproducible evaluation instead of the rolling `jev-latest`.

## Request

```
POST {JEV_BASE_URL}{JEV_API_PATH}            # default https://jev-ai.org/api/v1/systemone/ (trailing slash)
Authorization: Bearer $JEV_API_KEY
Content-Type: application/json
Idempotency-Key: <decision run id>

{ "model": "jev-1.13",
  "state": "Title: …\nCommunity: …\nContent:\n…",
  "questions": {
    "relevance": { "type": "noul", "instructions": "…" },
    "vertical":  { "type": "choice", "instructions": "…", "criteria": { "hr_recruiting": "…" } },
    "anger":     { "type": "score",  "instructions": "…", "criteria": ["Calm", "Angry"] }
  } }
```

`choice` criteria are an object (label → boundary description); `score` criteria are an array ordered
low to high. The typed `QuestionCriteria` enum makes the swap impossible, and it is marked
`#[serde(untagged)]`: without that, serde wraps a newtype variant as `{"Choice": {...}}` and the
provider reads it as a single label named `Choice`. A unit test pins both wire shapes. Limits enforced before the
call: 1–20 questions, state ≤ 100 000 characters, instructions ≤ 1 000 characters, choice 2–24 labels,
score 2–10 tiers.

## Response handling

The adapter reads `id`, `model`, `model_version`, `answers`, `usage.{input_tokens, output_tokens,
charged_tokens}` and `latency_ms`. Each answer is deserialized by its `type` tag; a missing answer for a
requested question is an `InvalidResponse` (never silently defaulted). Probabilities and confidence are
kept as reported: a probability is not treated as a confidence score, `noul` confidence is derived as
`|p - 0.5| * 2`, and `score` answers stay decimal (no rounding before thresholding).

## Questions asked

`domain::decision::lead_questions()` asks thirteen questions:
`relevance`, `business_problem`, `irrelevant_noise`, `vertical`, `intent`, `customer_type`,
`buying_intent`, `business_potential`, `product_fit`, `needs_human_review`, `evidence_sufficient`,
`too_ambiguous`, `language`. The language question offers 15 languages plus `other`; when the provider
answers `other`, the stored post language (detected locally) is preserved. The original text is never
translated before classification.

## Persistence

`decision_runs` stores provider, model, model version, request id, latency, tokens and status;
`decision_answers` stores each typed answer with probabilities. `provider_usage` records the call, and
`provider_costs` records an **unknown** cost because Jev bills per token without exposing a unit price
in this configuration. Do not present a computed cost as a charge.

## Errors

| Status | Mapping |
|---|---|
| 400 / 404 / 422 | `InvalidRequest`, permanent |
| 401 / 403 | `Unauthorized`, permanent |
| 409 | idempotency conflict, permanent (the original request holds the answer) |
| 429 | `RateLimited` with `Retry-After`, retryable |
| 5xx | `Unavailable`, retryable |
| transport/timeout | `Transport`, retryable |

Retries reuse the decision run id as `Idempotency-Key`, so a retry cannot buy a second decision.

## Not verified live

No Jev credential existed in this environment. The adapter is covered by wiremock contract tests using
the documented shapes; a real call remains an operator step (`POST /api/v1/providers/jev/test`).
