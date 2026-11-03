# Implementation status

Last updated from observed runs on this machine. Nothing here is aspirational.

## Verified automatically

| Area | State | Evidence |
|---|---|---|
| Domain rules (scoring, qualification, filtering, language, evidence, comment policy, job policy, cost guard) | implemented, unit tested | `cargo test --all-targets`: 96 library tests |
| Migrations and foreign keys | implemented, tested | migrations applied twice in `db::tests` |
| Provider contracts (Jev/Laya wire protocol, Qwen chat completions, Apify REST) | implemented, tested with `wiremock` | adapter test modules |
| API surface and OpenAPI document | implemented, tested | 17 integration tests in `tests/api.rs` |
| Tenant isolation | implemented, tested | `tenant_isolation_is_enforced_for_every_resource` |
| Import → normalization → decision → scoring → lead | implemented, tested | `import_pipeline_creates_one_qualified_lead`, Playwright pipeline spec |
| Duplicate suppression | implemented, tested | `duplicate_imports_do_not_create_a_second_lead` |
| Comment workflow (edit, approve, reject, manual publication) | implemented, tested | `comment_workflow_requires_explicit_human_actions` |
| No automatic publication | structural | no publishing code path; `AUTOMATIC_PUBLICATION_SUPPORTED = false`; UI has no publish action |
| Apify spend guard | implemented, tested | `apify_runs_pass_the_cost_guard_before_being_queued` + unit tests |
| Provider failure visibility | implemented, tested | unconfigured Jev test, provider status panel |
| Benchmarks (metrics, per language, unknown cost) | implemented, tested with mock | `benchmark_runs_against_the_seeded_evaluation_split` |
| Seeds idempotent | implemented, tested | `seeds_are_idempotent` |
| Job retry and dead letter | implemented, tested | `jobs_can_be_retried_and_dead_letters_are_visible` |
| Frontend action endpoint (form/JSON, origin policy, 4xx) | implemented, tested | `tests/e2e/action.spec.ts` (5 tests) |
| Source validation before enabling | implemented, tested | `sources_require_recorded_validation_before_enabling` |
| Provider-side run cap (`maxTotalChargeUsd`) | implemented, tested | adapter wiremock body assertion + config test |
| Frontend typecheck, lint, unit tests, build | passing | `astro check && vue-tsc`, `prettier --check`, Vitest (10 tests), `astro build` |
| End-to-end (dashboard, inbox, import pipeline, review queue) | passing | `./scripts/e2e-local.sh`: 3 Playwright tests |
| Docker images and Compose startup | verified | `docker build` for both images; `docker compose up -d` → api/worker/frontend healthy; `/health` and `/ready` 200 |
| Containerized import with unconfigured providers | verified behaviour | import stored the post, the decision job failed `dead_letter` with `provider jev is not configured`, no lead was invented |

## Verified against live services

Credentials were configured later by the operator; the following probes were run from this workspace.

| Integration | State |
|---|---|
| Apify credentials | **verified live**: `GET /v2/users/me` answered 200 (510 ms) |
| Apify Actor run, dataset paging, cancel | adapter implemented and contract-tested; **no live run executed** (no Actor registered yet) |
| Qwen generation | **verified live** (DashScope International, `qwen-plus`): `/v1/models` 200, minimal probe `ok` (1074 ms), 3/3 English variants stored, 3/3 Spanish variants stored with `Aviso: trabajo en VoxTranslate.`, no corrective pass needed |
| Jev decisions | **verified live** (TypeSafe deployment, `api.typesafe.ai/v1/systemone`, `jev-1.14.0`): real label distributions, 1546/590 tokens, 307 ms latency; the full pipeline produced a lead (score 79, `needs_review`) and Qwen drafted 3/3 comments |
| Laya decisions | adapter implemented; disabled by default, no key configured |
| Reddit / community validation | 17 of the 24 seeded communities were relevance-reviewed and enabled with evidence recorded through the API (HR, international work, events/AV, support, hospitality); 7 were excluded with a note (IT operations, broadcast engineering, generic sales/SaaS, travel agents, smallbusiness). Reddit terms and per-subreddit rules remain the operator's responsibility |

### Defect found and fixed by the live verification

The first live Jev run stored the literal label `Choice` for every choice answer. Cause: `QuestionCriteria`
serialized as `{"Choice": {...}}` because serde's default newtype representation wraps the variant; the
provider answered the only label it saw. Fixed with `#[serde(untagged)]` plus regression tests on the
domain type and on the adapter's request body. Mock providers and the mocked wire test had not exposed
it because neither inspects the criteria envelope.

### Observed product limitation

The seeded keyword lists are English (as specified). A post written only in another language is
filtered out before any paid call unless its vertical profile has keywords in that language. Adding
Spanish keywords through `PATCH /api/v1/search-profiles/:id` made the Spanish post pass the filter and
reach the decision stage; language-aware keyword coverage is an operator configuration task.

## Blocked or intentionally out of scope

- Real provider credentials and a validated Actor id (operator-supplied). The container stack was started
  without them, so the pipeline stopped exactly where it must: a visible provider error, no fake lead.
- PostgreSQL: schema and repositories are portable, but no PostgreSQL migration was written.
- Redis or another broker: the durable queue is SQLite by design.
- Rate limiting inside the application: expected from the reverse proxy.
- OAuth/OIDC: the MVP uses bearer tokens stored as hashes.

## Manual steps still required

1. `cp .env.example .env`, set `APIFY_API_TOKEN`, `JEV_API_KEY` and `QWEN_*` if those services will be
   used, and keep `DECISION_PROVIDER=jev`, `GENERATIVE_PROVIDER=qwen`, `SOURCE_PROVIDER=apify`.
2. `make migrate && make seed`, then start the stack with `make up`.
3. Register the Actor id you verified (`POST /api/v1/providers/apify/actors`), record validation and
   enable it (`PATCH /api/v1/providers/apify/actors/:id`).
4. Validate the communities you intend to monitor, with evidence, before enabling them.
5. Probe each configured provider once (`POST /api/v1/providers/:provider/test`) and confirm the billed
   cost in the provider console.
6. Import real conversations from an authorized source and review the decisions before trusting scores.
