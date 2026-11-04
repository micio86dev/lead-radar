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

## Applying variable changes

`railway restart` and `railway redeploy` reuse the **environment snapshot of the existing deployment**,
so a new value does not reach the container: the seed keeps reporting `bootstrap_token_created=false` and
the new token is rejected. Only a **new deployment from source** (`railway up`, or a deploy from the
dashboard) applies the current variables. `--skip-deploys` is still useful to batch several variable
writes, but finish with one `railway up`.

## Token rotation

`BOOTSTRAP_API_TOKEN` is the single source of truth. To rotate: set the new value on the backend, set the
same value as `LEAD_RADAR_API_TOKEN` on the frontend, then deploy (`railway up`). On every start the stack
entrypoint runs `db prune-tokens`, which deletes bootstrap token rows whose hash is not the configured
one, so the previous token stops working immediately instead of lingering.

`railway.json` (Config as Code) still works but is deprecated: Railway retires it on 2026-12-01 in
favour of Infrastructure as Code (`.railway/railway.ts`, `railway config migrate`).

## Volume ownership

Railway mounts the volume as root while the image runs as UID 10001, so SQLite fails with
`unable to open database file` unless the ownership is repaired. `deploy/entrypoint.sh` starts as root,
fixes `/data` (directory and database files only, no recursive walk), then drops to UID 10001 with
`setpriv`. If `setpriv` is missing the entrypoint refuses to run as root instead of silently doing so.

## Verified state

The first deployment was exercised end to end: `/health` and `/ready` answer, the seeds create the tenant,
profiles, communities, keywords, scoring v3 and the bootstrap token, the provider panel reports the
decision and generative providers as configured, a manual import produced a lead through a real decision
call, and three comment drafts were stored for review. The dashboard renders through private networking
with the server-side token.

## Caveats

- SQLite on a volume is a single-node design: no horizontal scaling, and the volume is the backup unit
  (`db purge` and `DELETE /api/v1/opportunities/:id` handle retention).
- A Railway redeploy rebuilds the Rust release image; the first build is the long one.
- The frontend reads the API token server-side only; it is never part of the browser bundle.
- Migrations run on every container start (they are versioned and idempotent).

## Reply queue cron

The service `lead-radar-cron` runs `deploy/cron/Dockerfile` (alpine + bash + curl, entrypoint
`scripts/prepare-queue.sh`) on the schedule `0 * * * *`, so the queue is refilled even when nobody opens the
dashboard.

- Build: `RAILWAY_DOCKERFILE_PATH=deploy/cron/Dockerfile`, pushed from the repository root
  (`.railwayignore` keeps `target/`, `node_modules/`, `data/`, `.env` out of the upload).
- Variables: `API_BASE=http://backend.railway.internal:8080` (private networking, no public hop),
  `API_TOKEN` (bootstrap token), `LIMIT=3`.
- The schedule lives on the service instance (`cronSchedule`), not in the image; a cron service runs its
  start command once per tick and exits.
- Logs: `railway logs -s lead-radar-cron`; each run prints one JSON line such as
  `{"job_ids":[],"queued":0}` (`queued: 0` is normal once every lead has drafts, or inside the cooldown).
- The backend caps automatic runs at three drafts with a ten-minute cooldown, so an hourly tick never
  amplifies provider spending.

## Deploying a service (the only supported path)

`railway up` resolves the upload root through Git. A submodule's `.git` is a file, so running it
inside `lead-radar-frontend` or `lead-radar-backend` uploads the **parent repository**: Railpack
analyzes the wrong tree, ignores the submodule's `railway.json`, and the build fails before it starts
(this happened twice on 2026-11-04 and left production untouched).

Deploy through the script, which exports the committed tree and refuses to ship uncommitted or
unpushed work:

```
make deploy-backend        # or: scripts/deploy-railway.sh backend
make deploy-frontend       # or: scripts/deploy-railway.sh frontend
```

It runs `git archive HEAD` into a scratch directory, checks that `Dockerfile` and `railway.json` are
in the exported tree, links that directory to the project, environment and service, then runs
`railway up --ci`. The Railway service keeps `builder: DOCKERFILE` with `dockerfilePath: /Dockerfile`
resolved against the upload root, which is why the export must contain the Dockerfile.

The local Docker stack is separate: after a change to `package.json` or `Cargo.toml`, rebuild the
images with `docker compose build` before `docker compose up -d`.

