# Qwen integration

Implementation: `lead-radar-backend/src/providers/qwen.rs`. Qwen is the initial generative model for
deeper analysis and comment drafts. It is completely separate from the model used to build the project.

## Configuration

`QWEN_BASE_URL` (an OpenAI-compatible base URL), `QWEN_API_KEY`, `QWEN_MODEL`, `QWEN_TIMEOUT`,
`QWEN_MAX_TOKENS`. Both base-URL conventions are accepted: `https://host` and
`https://host/compatible-mode/v1` (the OpenAI SDK convention); the adapter appends `/v1` only when the
configured base does not already end with it. It then posts to `{base}/v1/chat/completions` (or
`{base}/chat/completions`) with:

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
  the helpful variant, 40–1200 characters.
- The prompt quotes **the same rules the validator enforces** (`FORBIDDEN_PHRASES`,
  `PROMOTIONAL_PHRASES`, and the per-language `DISCLOSURE_EXAMPLES` in `domain::comment.rs`), so the
  model is told the exact disclosure form instead of discovering it by rejection. A unit test asserts
  every documented example satisfies the validator.
- If a draft still fails, exactly **one** corrective pass is made with the same provider, quoting the
  failed checks and asking only for the failed variants. There is no fallback to another provider and no
  second retry: remaining failures are reported in `ai_analyses` and the valid drafts are stored.
- Stored drafts start at `pending_review`. There is no automatic approval or publication path.

## Verified live

With a DashScope International key and `QWEN_MODEL=qwen-plus`:

- `GET {base}/models` → 200 (79 Qwen models visible).
- Minimal probe (`POST /api/v1/providers/qwen/test`) → `ok`, 1074 ms, JSON object accepted.
- Full pipeline on an English post (mock decision, real Qwen): 3/3 variants stored at the first attempt,
  no corrective pass.
- Full pipeline on a Spanish post: lead language `es`, 3/3 Spanish variants stored, both pitch variants
  opening with `Aviso: trabajo en VoxTranslate.`, no corrective pass.

## Usage and cost

`provider_usage` records `prompt_tokens`/`completion_tokens` and latency; `ai_analyses` keeps the raw
JSON payload and the stored analysis. Token prices are not configured, so the cost row is marked
unknown.

## Failure handling

Timeouts come from `QWEN_TIMEOUT`; retries are bounded by the worker (exponential backoff, max
attempts, dead letter). The adapter performs one attempt per call and never falls back to another paid
provider. An error is visible in `ai_analyses.error`, the job history and the provider status panel.
