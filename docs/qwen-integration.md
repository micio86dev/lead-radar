# Qwen integration

Implementation: `lead-radar-backend/src/providers/qwen.rs`. Qwen is the initial generative model for
deeper analysis and comment drafts. It is completely separate from the model used to build the project.

## Configuration

`QWEN_BASE_URL` (an OpenAI-compatible base URL), `QWEN_API_KEY`, `QWEN_MODEL`, `QWEN_TIMEOUT`,
`QWEN_MAX_TOKENS`. The adapter posts to `{QWEN_BASE_URL}/v1/chat/completions` with:

```json
{ "model": "<configured>", "messages": [{"role":"system",...},{"role":"user",...}],
  "temperature": 0.2, "max_tokens": 1200, "response_format": {"type": "json_object"}, "stream": false }
```

Nothing is hardcoded: an unset base URL, key or model leaves the adapter `unconfigured`, and the
comment-generation endpoint answers `503 not_ready` instead of pretending to work.

## Responsibilities

Qwen analyses selected opportunities (summary, evidence-grounded explanation, suggested approach) and
drafts three comment variants. It **never** computes the lead score and never publishes. The normal
pipeline uses the decision provider first and only sends selected candidates to Qwen.

## Validation

- The response body must contain `choices[0].message.content`, and that content must parse as a JSON
  **object**; anything else is an `InvalidResponse`.
- Comment drafts then pass the comment policy (`domain::comment::validate`): original language,
  disclosure for pitch variants, no invented experience/testimonials/pricing, no promotional language in
  the helpful variant, 40–1200 characters. Drafts that fail are not stored; the issues are recorded in
  `ai_analyses`.
- Stored drafts start at `pending_review`. There is no automatic approval or publication path.

## Usage and cost

`provider_usage` records `prompt_tokens`/`completion_tokens` and latency; `ai_analyses` keeps the raw
JSON payload and the stored analysis. Token prices are not configured, so the cost row is marked
unknown.

## Failure handling

Timeouts come from `QWEN_TIMEOUT`; retries are bounded by the worker (exponential backoff, max
attempts, dead letter). The adapter performs one attempt per call and never falls back to another paid
provider. An error is visible in `ai_analyses.error`, the job history and the provider status panel.
