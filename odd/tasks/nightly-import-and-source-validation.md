# Nightly import and source validation

Feature: close the two operator dead ends seen in production — a source that cannot be enabled because
nothing records its validation, and opportunities that can only be imported by hand — and put the manual
import one click away from where the operator looks for leads.

## Specs

- **S1** — The user's request, verbatim: "in prod non risco ad importare le opportunities, non vedo il
  pulsante che lo fa. E poi non riesco ad abilitare apify dalla pagina sources, mi da questo errore:
  "conflict: source_not_validated: record validation before enabling this source"". Added in the same
  session, verbatim: "aggiungi anche un cron schedulato a mezzanotte che importa automaticamente le
  opportunities".
- **S2** — `/sources` offers on every row the validation form `/communities` already has: `evidence`
  (required — the API answers 422 without it) and `outcome` (`validated` or `rejected`). Submitting it
  records the validation and the row's status changes; the API contract, the audit entry and the rule that
  enabling is a separate explicit step stay as they are.
- **S3** — A row whose source is neither `validated` nor `manual_import` says that validation must be
  recorded before it can be enabled, so the 409 the user hit in production names its own fix on screen. The
  table's `Notes` column also gets the header it was missing (the header row had seven cells for eight).
- **S4** — Manual import (`/import`) is reachable in one click from where opportunities are looked for: an
  `Import JSON` action in the Opportunities page header, and an action inside both "no opportunities" empty
  states (inbox and dashboard). The import page, its form and the API it posts to are unchanged.
- **S5** — `scripts/apify-community-sweep.py --scheduled` performs the nightly import: one Apify run per
  community that is enabled **and** validated (the same set the product rule allows to be collected), one at
  a time, waiting for each run to reach a terminal state before the next.
- **S6** — Unattended spend stays inside the ceilings that already exist: every run passes the server-side
  cost guard (kill switch, configured provider, actor enabled and validated, per-run cost cap, daily
  ceiling, concurrency). The first refusal stops the sweep for that night; the reason is reported in the
  summary line and nothing is retried.
- **S7** — After the sweep, the nightly run re-ingests datasets that cost nothing new: succeeded runs from
  the last `--reingest-days` days that carry a dataset and at least one item, minus the runs this pass just
  started, capped at `--reingest-limit`. Duplicate suppression by content hash keeps a re-read dataset from
  creating a second lead.
- **S8** — The schedule is 00:00 UTC. A Railway cron service `lead-radar-nightly` runs the same cron image
  in `CRON_MODE=nightly`; the hourly reply-queue cron (`lead-radar-cron`) keeps its schedule and behaviour.
  Locally the same script runs from `make nightly-import`, and the compose `scheduler` service keeps its
  hourly prepare loop.
- **S9** — Each nightly run prints exactly one JSON line for the service log:
  `{"queued":n,"refused":n,"reingested":n,"stopped_reason":null|"<guard reason>","actor":…}`.

## Tasks

- [x] T1 · S2, S3 · frontend: validation form on `/sources`, validation-required hint, `Notes` header · commit 93e61bb (frontend)
- [x] T2 · S4 · frontend: `Import JSON` entry point on the Opportunities header and both empty states · commit 5932c1f (frontend)
- [x] T3 · S5, S6, S7, S9 · root: `--scheduled` sweep mode with the re-ingestion phase and its stub test · commits b65b31a, 4f2f727
- [x] T4 · S8 · root: cron image mode, entrypoint, compose profile, Makefile target, deploy and operations docs · commits 4179717, d9729a9
- [x] T5 · S6 · backend: report the ceilings and kill switch the guard enforces · commit 4c8706e (backend) + d9729a9

## Log

- L1 (user): see S1.
- L2 (evidence, 2026-11-05): prod `/sources` (frontend-production-2223) renders two rows —
  `apify-default` (apify/community_feed, pending, disabled) and `manual-import` (manual_import, validated,
  enabled) — and only the `source.create`, `source.patch` and `source.test` forms. The API route
  `POST /api/v1/sources/{id}/validate` exists and works; the 409 the user saw is the enable guard in
  `patch_source`. No UI could produce that validation, so the source could never be enabled.
- L3 (evidence, 2026-11-05): prod `/import` answers 200 and its form already carries the `Import` submit
  button, and the sidebar links `/import`; the gap was discoverability from the inbox, not a missing page.
- L4 (decision, user): import visibility = "Solo più visibilità al link"; nightly data source = "Sweep +
  re-ingest"; nightly budget = "Ceiling giornaliero + kill switch"; timezone = UTC.
- L5 (evidence): `api/v1/providers/apify/runs` exposes `status`, `items_count`, `dataset_id` and
  `created_at`, and `POST …/runs/{id}/reingest` queues the dataset job, so the nightly script needs no new
  backend surface.
- L6 (evidence): `make test-scripts` runs the stub suite (37 checks, no network); the cron image builds and
  its three dispatch paths were exercised with no reachable API.
- L7 (slice note): T3 is one commit of 763 authored lines because it is the high-risk unit — the sweep script
  and the test that pins its spend bounds belong together so review can take them alone. T4 (delivery) was
  committed separately for the same reason.
- L8 (decision, operator pending): creating the Railway service `lead-radar-nightly`, setting its variables
  and deploying are the operator's call (the deploy script refuses unpushed work); the exact commands are in
  `docs/deploy-railway.md`.
- L9 (incident, 2026-11-05): while checking the entrypoint with `CRON_BIN_DIR` pointed at the repository, the
  nightly mode ran once against the **local** stack, which carries a real `APIFY_API_TOKEN`. One Apify run
  started (`0.02 USD`, 0 items) and was aborted through the API within two minutes; no other run was queued.
  The stub suite is the only supported way to exercise the nightly mode.
- L10 (evidence, 2026-11-05): the live deployment has the kill switch **engaged** in the stored override
  (`GET /api/v1/settings` → `budgets.kill_switch: true`), while `GET /api/v1/providers/apify/usage` and the
  dashboard reported `false` because they read the environment defaults. So the nightly pass cannot spend
  anything until the operator disengages it, and the pages that govern spending were lying. Fixed in 4c8706e
  (backend) with a test that reproduces the divergence, bumped in d9729a9.
- L11 (verification gap): `gentle-ai-verify` and `jd-judge-a` are unusable in this environment — both abort
  before their first tool call ("assistant reported an error", 0 tokens after 3 retries) because their pinned
  models (`opencode-go/space-bunny-free`, `opencode-go/kimi-k3`) fail on every request; a one-line smoke task
  fails the same way. Independent review is therefore missing for the high-risk unit, and the executable
  evidence was strengthened instead: 60 stub checks, including a refusal at the first, second and third
  attempt each proving no retry, plus the backend guard tests and the new reporting-parity test.
- L12 (independent verification, 2026-11-05): `gentle-ai-verify` ran (after its model was repointed from the
  removed `opencode-go/space-bunny-free` to `opencode-go/deepseek-v4.1-flash` in
  `~/.pi/gentle-ai/models.json`, `~/.pi/agent/subagents.json` and the three Pi agent profiles; Claude Code
  keeps its own `~/.claude/agents/*.md` with `model: sonnet`, untouched) and reported three blocking defects:
  (B1) a failed actor listing exited without the JSON line, (B2) a night that queued nothing exited 0, (B3)
  the sweep moved on to the next community after its wait expired, so a slow run pushed the concurrency guard
  into truncating the night. Plus advisories: a non-JSON line on the `no_communities` path, no summary on
  `--scheduled --dry-run`, an inert `--cap-usd` flag, a stale docstring, and uncaught exceptions producing no
  line at all.
- L13 (fixes): all of them fixed in one batch. The actors listing is tolerant and reports `actor_list_failed`;
  `no_communities` writes to stderr; the dry run prints its own summary; `run_not_terminal` stops an
  unattended pass instead of stacking runs; the wait and poll interval are `SWEEP_WAIT_SECONDS` /
  `SWEEP_POLL_SECONDS`; the banner names the registry charge cap instead of a flag that was never sent; the
  entry point catches unexpected exceptions and still prints the line; a night that queued nothing exits 3,
  so the platform shows it. The stub suite grew to 71 checks (bound, actor listing down, stalled run, dry-run
  summary, refusal at each attempt with the new exit code).
