# Source and community compliance

Lead Radar does not scrape Reddit directly and never bypasses authentication, access restrictions,
CAPTCHAs, rate limits or platform protections. Acquisition happens through an authorized provider
(Apify Actor) that the operator has verified, or through manual JSON imports.

## Activation checklist (per community and per Actor)

Record the outcome through the API; it is stored with evidence and an audit entry.

1. **Existence and activity** — does the community exist and is it active?
2. **Access method** — which authorized provider/Actor collects the data, and how?
3. **Terms** — do the source terms allow programmatic collection for this use?
4. **Commercial use** — is commercial research/outreach permitted, or does it need permission?
5. **Privacy and retention** — is personal data minimized, and is the retention window acceptable?
6. **Engagement rules** — does the community allow promotional replies, and what disclosure is required?

`POST /api/v1/communities/:id/validate` requires `evidence` and records `validated` or `rejected`.
Enabling a community whose status is not `validated` is refused with `409 conflict`. Communities are
seeded as `pending` and disabled: a seed never asserts permission.

## Actors

An Actor is registered with the exact `actor_id` the operator verified, stored disabled and pending.
`PATCH /api/v1/providers/apify/actors/:id` records validation and enables it. The registry keeps a
`source_type` and an input template, so a second Actor is configuration, not code.

## Reddit-specific rules of thumb

- Prefer the official API or a licensed provider; respect its rate limits and user-agent requirements.
- Do not collect deleted or private content once removal is known; `DELETE /api/v1/opportunities/:id`
  removes stored content and unreviewed drafts.
- Never post automatically. Replies are drafted, reviewed and published by a human, who records the
  publication. Lead Radar has no publishing capability at all.
- Keep evidence verbatim and attribute the original URL; never paraphrase a quote as a fact.

## Deletion requests

Use `DELETE /api/v1/opportunities/:id` (content overwrite, lead deactivation, draft removal, audit
entry). For bulk retention, `db purge [days]` overwrites content older than the configured window.
