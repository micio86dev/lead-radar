# Testing

No automated test reaches a paid service. Providers are replaced by deterministic mocks, HTTP contracts
by `wiremock`, and every test uses its own temporary SQLite database.

## Backend

```bash
cd lead-radar-backend
cargo test --all-targets     # unit + integration
cargo clippy --all-targets -- -D warnings
cargo fmt --all -- --check
```

- **Unit tests** live next to the code: enums round-trip, scoring weights/bands/renormalization,
  qualification gates, keyword filtering boundaries, language detection, evidence offsets, benchmark
  metrics, comment policy, job backoff/state machine, cost guard, task config validation.
- **Provider contract tests** (`wiremock`): documented request body, required headers (including
  `Idempotency-Key`), strict response parsing, missing answers, malformed JSON, 401/404/429 with
  `Retry-After`, 5xx, unconfigured adapters performing no call, Apify run status and dataset paging.
- **Integration tests** (`tests/api.rs`) drive the real router through `tower::ServiceExt::oneshot`
  against a fresh database: auth, import → lead pipeline, duplicate imports, tenant isolation, comment
  workflow (edit/approve/reject/manual publication), unconfigured provider visibility, cost guard and
  settings-driven ceilings, community validation rules, search-profile CRUD, dashboard aggregates,
  benchmark execution on the seeded split, seed idempotency, job retry, engagements, content removal,
  input validation.
- **Migrations** are tested by applying them twice and by verifying a foreign-key violation is refused.

Coverage target: 85 % of domain modules (`cargo llvm-cov --summary-only`). Report the measured number,
never an assumption.

## Frontend

```bash
cd lead-radar-frontend
bun run typecheck    # astro check + vue-tsc --noEmit
bun run lint         # prettier --check
bun run test         # vitest: formatting and query helpers
bun run build
```

`tests/e2e/*.spec.ts` (Playwright) needs a running stack. `scripts/e2e-local.sh` builds the backend,
creates a temporary database, seeds it with offline providers, starts api + worker + the prebuilt
frontend and runs the suite:

```bash
./scripts/e2e-local.sh
```

Scenarios covered end to end: the dashboard renders and the navigation is keyboard reachable; the
opportunities inbox renders rows or an empty state; a manual JSON import reaches the inbox through the
worker and its detail page shows content plus the score breakdown; the review queue renders; no
publication surface exists.

## Smoke test against a running stack

`./scripts/smoke-live.sh` exercises the real stack (real providers, real worker): it imports one
conversation whose text matches the seeded keywords, waits for the worker to create the lead, and prints
the score, the decision metadata and the URLs to continue in the browser. It uses the bearer token from
`.env` and never prints it.

```bash
./scripts/smoke-live.sh
# then open the printed /opportunities/<id>, click "Draft three comment variants",
# and review them at /review
```

The import and the structured decision are billed; the comment drafting is a separate, explicit click.
A failure prints the job queue state (`GET /api/v1/jobs`) instead of guessing.

Run it after rebuilding the images (`docker compose build api`) — a stale image explains most "why is
this broken" moments.

## What is not covered

- Live calls to Apify, Jev, Laya and Qwen: no credentials existed in the build environment. The adapters
  are verified against documented shapes with `wiremock`; live verification is an operator step.
- Browser rendering of every page under every viewport: the accessibility rules are implemented and
  spot-checked, not exhaustively audited.
- Load testing: the design bounds concurrency, but no benchmark run was executed.
