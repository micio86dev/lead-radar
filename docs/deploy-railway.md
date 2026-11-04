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
railway add --service backend
railway add --service frontend

# secrets come from .env; use --stdin so the value never appears in argv
railway variable set -s backend APP_ENV --stdin <<< production

railway volume add -s backend --mount-path /data
railway up -s backend --detach          # from lead-radar-backend/
railway up -s frontend --detach         # from lead-radar-frontend/
railway domain -s frontend              # public dashboard URL
railway logs -s backend
```

## Caveats

- SQLite on a volume is a single-node design: no horizontal scaling, and the volume is the backup unit
  (`db purge` and `DELETE /api/v1/opportunities/:id` handle retention).
- A Railway redeploy rebuilds the Rust release image; the first build is the long one.
- The frontend reads the API token server-side only; it is never part of the browser bundle.
- Migrations run on every container start (they are versioned and idempotent).
