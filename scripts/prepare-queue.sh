#!/usr/bin/env bash
# Keeps the reply queue full: asks the API for a bounded batch of drafts.
#
# The endpoint rate limits automatic preparation (ten-minute cooldown per tenant) and caps the batch at
# three, so running this every hour is safe and a manual run is never blocked.
#
# Usage:
#   scripts/prepare-queue.sh                # auto: bounded, respects the cooldown
#   scripts/prepare-queue.sh --manual       # explicit button semantics, bypasses the cooldown
#   scripts/prepare-queue.sh --dry-run      # print the request without the token and exit
#
# Environment:
#   API_BASE   base URL of the API (default: http://localhost:8080)
#   API_TOKEN  bearer token (falls back to DEV_API_TOKEN, then BOOTSTRAP_API_TOKEN)
#   LIMIT      drafts to request (default 3, clamped 1-10 by the API)
#   LOG_FILE   append one line per run (rotated at 1 MB to LOG_FILE.1)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
LIMIT="${LIMIT:-3}"
MODE="auto"
DRY_RUN="false"

while [ $# -gt 0 ]; do
  case "$1" in
    --limit) LIMIT="$2"; shift 2 ;;
    --manual) MODE="manual"; shift ;;
    --dry-run) DRY_RUN="true"; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

# Read one key from the env file without executing it.
from_env_file() {
  [ -f "$ENV_FILE" ] || return 0
  grep -E "^$1=" "$ENV_FILE" | tail -1 | cut -d= -f2- | sed -e 's/^["'\'']//' -e 's/["'\'']$//'
}

API_BASE="${API_BASE:-$(from_env_file PUBLIC_API_BASE_URL)}"
API_BASE="${API_BASE:-http://localhost:8080}"
API_BASE="${API_BASE%/}"

API_TOKEN="${API_TOKEN:-${DEV_API_TOKEN:-}}"
if [ -z "$API_TOKEN" ]; then
  API_TOKEN="$(from_env_file DEV_API_TOKEN)"
fi
if [ -z "$API_TOKEN" ]; then
  API_TOKEN="$(from_env_file BOOTSTRAP_API_TOKEN)"
fi

if [ -z "$API_TOKEN" ]; then
  echo "prepare-queue: no API token (API_TOKEN, DEV_API_TOKEN or BOOTSTRAP_API_TOKEN)" >&2
  exit 3
fi

if [ "$MODE" = "auto" ]; then
  BODY="{\"limit\":${LIMIT},\"auto\":true}"
else
  BODY="{\"limit\":${LIMIT}}"
fi

if [ "$DRY_RUN" = "true" ]; then
  echo "POST ${API_BASE}/api/v1/reply-console/prepare"
  echo "  body:   ${BODY}"
  echo "  bearer: <${#API_TOKEN} characters>"
  exit 0
fi

response_file="$(mktemp)"
trap 'rm -f "$response_file"' EXIT
status="$(curl -sS --max-time 30 -o "$response_file" -w '%{http_code}' \
  -X POST "${API_BASE}/api/v1/reply-console/prepare" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H 'Content-Type: application/json' \
  -d "$BODY" || echo 000)"
body="$(cat "$response_file")"

if [ -n "${LOG_FILE:-}" ]; then
  mkdir -p "$(dirname "$LOG_FILE")"
  if [ -f "$LOG_FILE" ] && [ "$(wc -c <"$LOG_FILE")" -gt 1048576 ]; then
    mv "$LOG_FILE" "$LOG_FILE.1"
  fi
  printf '%s status=%s body=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$status" "$body" >>"$LOG_FILE"
fi

if [ "$status" != "202" ] && [ "$status" != "200" ]; then
  echo "prepare-queue: HTTP ${status}: ${body}" >&2
  exit 1
fi

echo "$body"
