# Projects and automatic community matching

Feature: stop hardcoding the product. An operator keeps several projects, each with its own
description and public URLs, and the system ranks the already-active communities that fit a project
by analysing that material. Opportunity import stays manual.

Status: **specified, not implemented**. The engagement policy shipped first because a ban on the
account blocks the whole channel.

## Specs

- **S1** — The user's request, verbatim: "ora voxtranslate è hardcodato, vorrei invece poter gestire
  più progetti e per ognuno posso mettere dei dati e degli url del sito, pagine web... da cui parte
  un'analisi con qwen e/o jev per assegnare automaticamente le communities più interessate al
  prodotto, già attivate e funzionanti e l'import delle opportunities lo teniamo sempre manuale com'è
  adesso."
- **S2** — A `project` belongs to a tenant and carries a name, a free-text description (what the
  product is, in the operator's words), an optional list of public URLs, and the node's timestamps.
  Exactly one project per tenant is `is_default`: it supplies the context the drafting prompts use.
  CRUD lives at `/api/v1/projects` and on a `/projects` page.
- **S3** — No runtime code contains a product description. The generative and analysis paths read the
  default project. When no project exists they fail visibly with a message naming the missing
  configuration instead of inventing one. The previous hardcoded text is preserved by a data
  migration that creates one default project per existing tenant, so no behaviour is lost and the
  constant disappears from the code.
- **S4** — `POST /api/v1/projects/{id}/match-communities` sends the project description plus the text
  of its fetched URLs to the configured generative provider and asks for a relevance verdict
  (0–100) and a one-line reason per candidate. Candidates are only communities that are *validated
  and enabled* in that tenant — a match never activates, validates or disables anything. Results are
  stored in `project_communities(project_id, community_id, relevance, reason, matched_at)` and
  replaced on each run. A failed or unparseable provider answer stores nothing and reports the
  failure; no partial ranking is ever presented as complete.
- **S5** — URL fetching is bounded and safe, because the operator supplies the URLs: `http`/`https`
  only, at most 5 URLs, a redirect limit, a request timeout and a response size cap, and the
  destination IP must be public — loopback, private, link-local and cloud-metadata addresses are
  refused before the request is made. Each URL's outcome is reported per URL; nothing is skipped
  silently.
- **S6** — Opportunity import stays exactly as it is: manual JSON, or an Apify run the operator
  starts. Nothing in this feature collects content on a schedule.
- **S7** — The ranking is advisory. It changes no community state, publishes nothing, and the UI shows
  the reason next to the score so a human can disagree with it.

## Tasks

- [ ] T1 · S2 · migration `projects`, module with CRUD, tenant isolation, `/api/v1/projects` routes
- [ ] T2 · S3 · data migration of the current product text into a default project, and the prompt
      paths reading it (with a visible failure when it is missing)
- [ ] T3 · S5 · bounded fetch helper with the SSRF guard and per-URL outcomes, unit tested
- [ ] T4 · S4 · matching run over validated+enabled communities, `project_communities` storage,
      mock-provider tests for success, refusal and unparseable output
- [ ] T5 · S2, S4, S7 · `/projects` page: list, create/edit with URLs, run the analysis, show the
      ranked communities with their reason
- [ ] T6 · S6, S7 · docs: architecture and status pages, plus the statement that collection stays
      manual

## Log

- L1 (user): see S1.
- L2 (decision): a project is a first-class entity, not a tenant. Tenants already isolate data and
  memberships; making a product *be* a tenant would have forced a multi-tenant UI and broken the
  single-operator flow the product is built around.
- L3 (constraint): the URLs are operator-supplied and fetched server-side, so S5 is a security
  boundary, not a convenience. It is the reason T3 is its own task with its own tests.
- L4 (order): the community engagement policy (migration `0011`) shipped first: a removed comment and
  a one-account channel make publication safety the higher-priority unit.
