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
| Frontend typecheck, lint, unit tests, build | passing | `astro check && vue-tsc`, `prettier --check`, Vitest (10 tests), `astro build` |
| End-to-end (dashboard, inbox, import pipeline, review queue) | passing | `./scripts/e2e-local.sh`: 3 Playwright tests |

## Not verified against live services

No `APIFY_API_TOKEN`, `JEV_API_KEY`, `LAYA_API_KEY` or `QWEN_*` credential existed in this environment.

| Integration | State |
|---|---|
| Apify Actor run, dataset paging, cancel | adapter implemented and contract-tested; **no live run executed** |
| Jev decisions | adapter implemented against documented shapes; **no live call** |
| Laya decisions | adapter implemented; **no live call**; disabled by default |
| Qwen generation | adapter implemented; **no live call** |
| Reddit / community validation | workflow implemented; **validation is an operator decision and was not performed** |

## Blocked or intentionally out of scope

- Real provider credentials and a validated Actor id (operator-supplied).
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
