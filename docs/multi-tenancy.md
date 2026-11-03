# Multi-tenancy

Lead Radar is multi-tenant from the first migration, even when only one local tenant exists.

## Model

- `tenants` — the isolation boundary.
- `users` — global identities (`email` unique).
- `tenant_users` — membership with a role: `owner`, `admin`, `reviewer`, `viewer`.
- `api_tokens` — bearer tokens stored as SHA-256 digests, bound to `(tenant_id, user_id)`.

A request is authenticated by hashing the bearer token and looking up an active token. The resulting
`TenantContext { tenant_id, user_id, role, actor }` is the only source of `tenant_id`. There is no code
path that reads a tenant from a body, query string or path.

## Development identity

`DEV_API_TOKEN` (default `dev-local-token`) maps to the seeded tenant and owner user **only** when
`APP_ENV` is `development` or `test`. `AppConfig::validate` refuses to start with `APP_ENV=production`
and a `DEV_API_TOKEN` set, and production requires tokens persisted in `api_tokens`.

## Isolation guarantees

- Every repository function takes `tenant_id` and binds it.
- Cross-tenant reads return `404`, not `403`, so existence does not leak.
- The API test `tenant_isolation_is_enforced_for_every_resource` imports a lead as tenant A and asserts
  tenant B sees zero opportunities, cannot fetch A's lead, sees zero comments and its own dashboard.
- Audit logs are tenant-scoped.

## Roles

| Role | Can read | Can review comments | Can change settings/sources |
|---|---|---|---|
| `viewer` | yes | no | no |
| `reviewer` | yes | yes | no |
| `admin` | yes | yes | yes |
| `owner` | yes | yes | yes |

Role checks happen server-side (`TenantContext::require_reviewer`); the UI only reflects what the
server allows and never decides access.

## Adding a tenant

1. Insert the tenant, a user and a `tenant_users` membership (or extend the seed for local use).
2. Store the SHA-256 of the token the operator generated: `db token <plaintext>` prints the hash.
3. Insert the `api_tokens` row bound to that tenant and user.

There is no tenant-management API in the MVP; onboarding is an operator action performed with SQL or
`db token` plus a migration, which keeps the attack surface small.
