# Deploy on Railway

Railway runs containers, not Compose stacks. SQLite makes one constraint non-negotiable: **the API and the
worker must share the same volume**, so they run as **one service** through `deploy/stack.sh`
(migrations → idempotent seeds → worker in background → API in foreground). The dashboard is a second
service. That is two services, one volume, one project.

## Services

| Service | Source | Volume | Listens | Health |
|---|---|---|---|---|
| `backend` | `lead-radar-backend` (`Dockerfile` + `railway.json`) | `/data` (SQLite) | `APP_PORT=8080` | `GET /health` |
| `frontend` | `lead-radar-frontend` | none | Railway's `PORT` | `GET /health` |

## Environment

Backend (`railway variable set -s backend`; never paste secrets into a terminal you record):

| Variable | Value |
|---|---|
| `APP_ENV` | `production` (mock providers and the development token are refused) |
| `APP_HOST` / `APP_PORT` | `0.0.0.0` / `8080` |
| `DATABASE_URL` | `sqlite:///data/lead-radar.db?mode=rwc` |
| `BOOTSTRAP_API_TOKEN` | strong random value, at least 24 characters; seeds a hashed token row |
| `CORS_ALLOWED_ORIGINS` | the frontend public URL |
| `DECISION_PROVIDER` / `GENERATIVE_PROVIDER` / `SOURCE_PROVIDER` | `jev` / `qwen` / `apify` |
| `JEV_API_KEY`, `JEV_BASE_URL`, `JEV_API_PATH`, `JEV_MODEL` | as in `.env.example` |
| `QWEN_API_KEY`, `QWEN_BASE_URL`, `QWEN_MODEL` | as in `.env.example` |
| `APIFY_API_TOKEN`, budget and ceiling variables | as in `.env.example` |
| `WORKER_*`, `JOB_*`, `LOG_LEVEL` | as in `.env.example` |

Frontend:

| Variable | Value |
|---|---|
| `API_INTERNAL_URL` | `http://backend.railway.internal:8080` (private networking) |
| `PUBLIC_API_BASE_URL` | the backend public URL, used only for display links |
| `LEAD_RADAR_API_TOKEN` | the same value as `BOOTSTRAP_API_TOKEN` |
| `PORT`, `HOST` | `8080`, `0.0.0.0` |

`BOOTSTRAP_API_TOKEN` is read only while seeding, stored as a SHA-256 hash, and is safe to rotate: set a
new value, redeploy, and the new token is added (`ensure_api_token` is idempotent per hash) — remove the
old one from the database when the new one works.

## Commands

```bash
railway init --name lead-radar
railway add -s backend
railway add -s frontend

# secrets come from .env; --stdin keeps the value out of argv
railway variable set -s backend APP_ENV --stdin <<< production

# Volumes need the service *id*: with v5.68 a service name on the volume command panics.
railway status --json            # read environments[].serviceInstances[].serviceId
railway volume -p <project-id> -e <environment-id> -s <service-id> add -m /data

railway variable set -s backend PORT=8080                    # the edge probes this port
railway variable set -s frontend PORT=8080 HOST=0.0.0.0 \
  API_INTERNAL_URL=http://backend.railway.internal:8080 \
  PUBLIC_API_BASE_URL=<backend public domain> LEAD_RADAR_API_TOKEN=<bootstrap token>

railway domain -s backend        # public API domain (display/verification)
railway domain -s frontend       # public dashboard domain, also the backend CORS origin
railway up -p <project-id> -e production -s backend --detach    # from lead-radar-backend/
railway up -p <project-id> -e production -s frontend --detach   # from lead-radar-frontend/
railway logs -s backend
railway deployment list -s backend --json    # status while the Rust image builds
```

`railway.json` (Config as Code) still works but is deprecated: Railway retires it on 2026-12-01 in
favour of Infrastructure as Code (`.railway/railway.ts`, `railway config migrate`).

## Volume ownership

Railway mounts the volume as root while the image runs as UID 10001, so SQLite fails with
`unable to open database file` unless the ownership is repaired. `deploy/entrypoint.sh` starts as root,
fixes `/data` (directory and database files only, no recursive walk), then drops to UID 10001 with
`setpriv`. If `setpriv` is missing the entrypoint refuses to run as root instead of silently doing so.

## Caveats

- SQLite on a volume is a single-node design: no horizontal scaling, and the volume is the backup unit
  (`db purge` and `DELETE /api/v1/opportunities/:id` handle retention).
- A Railway redeploy rebuilds the Rust release image; the first build is the long one.
- The frontend reads the API token server-side only; it is never part of the browser bundle.
- Migrations run on every container start (they are versioned and idempotent).
