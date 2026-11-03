#!/usr/bin/env bash
# Boot an isolated local stack (SQLite temp database, offline providers) and run the Playwright suite.
# Nothing is published and no paid provider is called.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND="$ROOT/lead-radar-backend"
FRONTEND="$ROOT/lead-radar-frontend"
DB_PATH="$(mktemp -t lead-radar-e2e)"
API_PORT="${APP_PORT:-8080}"
FRONTEND_PORT="${FRONTEND_PORT:-4321}"

export APP_ENV=development
export APP_HOST=127.0.0.1
export APP_PORT="$API_PORT"
export DATABASE_URL="sqlite://${DB_PATH}?mode=rwc"
export DEFAULT_TENANT_ID="00000000-0000-0000-0000-000000000001"
export DEV_API_TOKEN="dev-local-token"
export DECISION_PROVIDER=mock
export GENERATIVE_PROVIDER=mock
export SOURCE_PROVIDER=mock
export LOG_LEVEL=warn
export RUST_LOG=warn

echo "== building the backend"
(cd "$BACKEND" && cargo build --bins >/dev/null)

echo "== migrating and seeding ${DB_PATH}"
"$BACKEND/target/debug/db" migrate
"$BACKEND/target/debug/db" seed

echo "== starting api and worker"
"$BACKEND/target/debug/api" &
API_PID=$!
"$BACKEND/target/debug/worker" &
WORKER_PID=$!

echo "== starting the frontend (prebuilt server output)"
(cd "$FRONTEND" && \
  API_INTERNAL_URL="http://127.0.0.1:${API_PORT}" \
  PUBLIC_API_BASE_URL="http://localhost:${API_PORT}" \
  LEAD_RADAR_API_TOKEN="dev-local-token" \
  HOST=127.0.0.1 PORT="$FRONTEND_PORT" \
  node ./dist/server/entry.mjs) &
FRONTEND_PID=$!

cleanup() {
  kill "$FRONTEND_PID" "$WORKER_PID" "$API_PID" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup EXIT

echo "== waiting for readiness"
for _ in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:${API_PORT}/ready" >/dev/null 2>&1 \
     && curl -fsS "http://127.0.0.1:${FRONTEND_PORT}/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo "== running Playwright"
(cd "$FRONTEND" && \
  E2E_BASE_URL="http://127.0.0.1:${FRONTEND_PORT}" \
  E2E_API_URL="http://127.0.0.1:${API_PORT}" \
  E2E_API_TOKEN="dev-local-token" \
  bun run test:e2e)
