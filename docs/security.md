# Security

## Secrets

- Only `.env` (untracked) and environment variables. `.env.example` documents names and safe defaults.
- `lead-radar-backend/.gitignore` ignores `.env`, `*.db` and `/data`.
- Provider keys are read in `src/config.rs` and never logged. Request logging records method, route,
  status and latency, not headers or bodies.
- The frontend reads the API token server-side only; no `PUBLIC_` variable ever carries it, and the
  token is not part of any client bundle.
- `AppConfig::validate` refuses production with `DEV_API_TOKEN`, mock providers or invalid budgets.

## Authentication and authorization

- Bearer tokens are compared as SHA-256 digests; plaintext tokens never reach the database.
- The tenant is derived from the token. Input-borne tenant ids are ignored.
- Reviewer-only endpoints (`PATCH /comments/:id`, approve, reject, record-publication) call
  `require_reviewer`, which rejects `viewer`.

## Input validation

- Every request body is validated before use: import payload size and field rules, enum membership for
  filters, RFC 3339 timestamps, bounded numbers, JSON-object-only settings and Actor templates.
- Errors use one envelope with field-level details and never echo secrets or full upstream bodies.
- SQL is always parameterised; the only dynamic SQL is a generated list of bound placeholders for
  whitelisted job kinds and filter clauses.

## External data

- Collected content is untrusted input. It is stored with provenance (`source_id`, `discovered_at`,
  `source_url`) and displayed as text, never executed. The UI links out with
  `rel="noopener noreferrer nofollow"`.
- Evidence excerpts are copied verbatim with character offsets; no generated claim is treated as fact.
- `DELETE /api/v1/opportunities/:id` overwrites stored content, marks the post deleted, deactivates the
  lead and removes unreviewed drafts, keeping an audit record.

## Provider boundaries

- Adapters validate requests before sending (question count, state size, criteria shape).
- Only transient failures are retried; a malformed request or a rejected key becomes a permanent job
  failure, so no paid call is repeated blindly.
- Health checks are explicit (`POST /api/v1/providers/:provider/test`) and may be billed; dashboards
  read recorded usage instead.

## Known limitations

- SQLite is a single-node store; there is no row-level encryption.
- Rate limiting is delegated to the reverse proxy/Ingress in front of the API; the application exposes
  no limiter of its own.
- Local development uses a static token by design; no OAuth/OIDC provider is implemented.
