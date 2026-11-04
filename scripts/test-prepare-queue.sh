#!/usr/bin/env bash
# Checks scripts/prepare-queue.sh against a local stub: request shape, exit codes and dry-run behaviour.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/prepare-queue.sh"
WORK_DIR="$(mktemp -d)"
REQUEST_LOG="$WORK_DIR/request.log"
STUB_PORT="${STUB_PORT:-18099}"
failures=0

cleanup() { [ -n "${STUB_PID:-}" ] && kill "$STUB_PID" 2>/dev/null || true; rm -rf "$WORK_DIR"; }
trap cleanup EXIT

cat >"$WORK_DIR/stub.py" <<'PY'
import http.server, json, sys
mode = sys.argv[2]
log_path = sys.argv[3]

class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('content-length', 0))
        body = self.rfile.read(length).decode()
        with open(log_path, 'a') as handle:
            handle.write(json.dumps({
                'path': self.path,
                'method': 'POST',
                'auth': self.headers.get('authorization', ''),
                'body': json.loads(body) if body else None,
            }) + '\n')
        status = 202 if mode == 'accept' else 401
        payload = {'job_ids': ['job-1'], 'queued': 1} if status == 202 else {'error': {'code': 'unauthorized'}}
        encoded = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header('content-type', 'application/json')
        self.send_header('content-length', str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, *args):
        pass

http.server.HTTPServer(('127.0.0.1', int(sys.argv[1])), Handler).serve_forever()
PY

start_stub() {
  python3 "$WORK_DIR/stub.py" "$STUB_PORT" "$1" "$REQUEST_LOG" &
  STUB_PID=$!
  for _ in $(seq 1 50); do
    curl -s -o /dev/null "http://127.0.0.1:${STUB_PORT}/" && return 0 || true
    sleep 0.1
  done
  echo "stub did not start" >&2
  exit 1
}

check() { # name, expected, actual
  if [ "$2" = "$3" ]; then
    echo "  ok   $1"
  else
    echo "  FAIL $1: expected [$2] got [$3]" >&2
    failures=$((failures + 1))
  fi
}

echo "prepare-queue.sh"

# 1. A successful run posts the bounded auto body with a bearer token and exits 0.
start_stub accept
out="$(API_BASE="http://127.0.0.1:${STUB_PORT}" API_TOKEN="test-token" ENV_FILE="$WORK_DIR/none" \
  "$SCRIPT" --limit 2 2>&1)" && code=0 || code=$?
check "exit code on 202" "0" "$code"
check "prints the response body" '{"job_ids": ["job-1"], "queued": 1}' "$(printf '%s' "$out" | tr -d '\n')"
request="$(tail -1 "$REQUEST_LOG")"
check "posts to the prepare endpoint" "/api/v1/reply-console/prepare" "$(printf '%s' "$request" | python3 -c 'import json,sys; print(json.load(sys.stdin)["path"])')"
check "sends the auto flag and the limit" '{"auto": true, "limit": 2}' "$(printf '%s' "$request" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["body"], sort_keys=True))' )"
check "sends a bearer token" "Bearer test-token" "$(printf '%s' "$request" | python3 -c 'import json,sys; print(json.load(sys.stdin)["auth"])')"
kill $STUB_PID 2>/dev/null || true; wait $STUB_PID 2>/dev/null || true; STUB_PID=""

# 2. --manual drops the auto flag so the cooldown is bypassed.
: >"$REQUEST_LOG"
start_stub accept
API_BASE="http://127.0.0.1:${STUB_PORT}" API_TOKEN="test-token" ENV_FILE="$WORK_DIR/none" \
  "$SCRIPT" --limit 5 --manual >/dev/null 2>&1 || true
check "--manual omits auto" '{"limit": 5}' "$(tail -1 "$REQUEST_LOG" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["body"], sort_keys=True))')"
kill $STUB_PID 2>/dev/null || true; wait $STUB_PID 2>/dev/null || true; STUB_PID=""

# 3. A rejection is a failure, not a silent success: cron must see the exit code.
start_stub reject
API_BASE="http://127.0.0.1:${STUB_PORT}" API_TOKEN="test-token" ENV_FILE="$WORK_DIR/none" \
  "$SCRIPT" >/dev/null 2>&1 && code=0 || code=$?
check "exit code on 401" "1" "$code"
kill $STUB_PID 2>/dev/null || true; wait $STUB_PID 2>/dev/null || true; STUB_PID=""

# 4. No token means no request at all.
API_BASE="http://127.0.0.1:${STUB_PORT}" ENV_FILE="$WORK_DIR/none" \
  "$SCRIPT" >/dev/null 2>&1 && code=0 || code=$?
check "exit code without a token" "3" "$code"

# 5. --dry-run never reaches the network.
out="$(API_BASE="http://127.0.0.1:${STUB_PORT}" API_TOKEN="test-token" ENV_FILE="$WORK_DIR/none" \
  "$SCRIPT" --dry-run)"
check "--dry-run prints the body" '{"limit":3,"auto":true}' "$(printf '%s\n' "$out" | sed -n 's/^  body:   //p')"
check "--dry-run hides the token" "<10 characters>" "$(printf '%s\n' "$out" | sed -n 's/^  bearer: //p')"

if [ "$failures" -ne 0 ]; then
  echo "prepare-queue.sh: $failures failure(s)" >&2
  exit 1
fi
echo "prepare-queue.sh: all checks passed"
