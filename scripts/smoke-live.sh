#!/usr/bin/env bash
# End-to-end smoke test against a running stack (no mocks): import one conversation, wait for the
# worker to create the lead, print where to click. Uses the bearer token from .env and never prints it.
#
#   ./scripts/smoke-live.sh                 # api :8080, frontend :4321
#   LEAD_RADAR_API_URL=http://host:8080 ./scripts/smoke-live.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${LEAD_RADAR_ENV_FILE:-$ROOT/.env}"
API_URL="${LEAD_RADAR_API_URL:-http://localhost:8080}"
FRONTEND_URL="${LEAD_RADAR_FRONTEND_URL:-http://localhost:4321}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "missing $ENV_FILE" >&2
  exit 1
fi
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a
TOKEN="${DEV_API_TOKEN:-${LEAD_RADAR_API_TOKEN:-}}"
if [[ -z "$TOKEN" ]]; then
  echo "DEV_API_TOKEN / LEAD_RADAR_API_TOKEN not set in $ENV_FILE" >&2
  exit 1
fi

echo "== readiness"
for endpoint in "$API_URL/ready" "$FRONTEND_URL/health"; do
  if curl -fsS --max-time 5 "$endpoint" >/dev/null; then
    echo "   ok: $endpoint"
  else
    echo "   FAIL: $endpoint is not answering" >&2
    exit 1
  fi
done

echo "== import one conversation"
export SMOKE_API_URL="$API_URL" SMOKE_TOKEN="$TOKEN" SMOKE_FRONTEND_URL="$FRONTEND_URL"
python3 - <<'PY'
import datetime, json, os, time, urllib.error, urllib.request

api = os.environ['SMOKE_API_URL'].rstrip('/')
token = os.environ['SMOKE_TOKEN']
frontend = os.environ['SMOKE_FRONTEND_URL'].rstrip('/')

def call(method, path, body=None, timeout=60):
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(
        api + path, data=data, method=method,
        headers={'authorization': 'Bearer ' + token, 'content-type': 'application/json'},
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read().decode()
            return response.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as error:
        raw = error.read().decode()
        return error.code, (json.loads(raw) if raw else None)

marker = f"smoke-{int(time.time())}"
published = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=1)).strftime('%Y-%m-%dT%H:%M:%SZ')
status, imported = call('POST', '/api/v1/import/json', {'posts': [{
    'external_id': marker,
    'title': f'Multilingual interviews block our hiring ({marker})',
    'content': ('Our recruiting team cannot interview candidates who only speak Spanish. '
                'We need real-time translation in the interviews, any suggestions? '
                'This is an international hiring problem we face every week.'),
    'url': f'https://example.invalid/{marker}',
    'author': 'smoke-author',
    'community': 'recruiting',
    'language': 'en',
    'published_at': published,
    'engagement': {'comments': 3, 'upvotes': 7, 'shares': 0},
}]})
print(f"   import: HTTP {status} | imported={imported.get('imported')} duplicates={imported.get('duplicates')}")
if status != 202:
    raise SystemExit('import failed')

lead_id = None
for _ in range(45):
    status, listing = call('GET', '/api/v1/opportunities?per_page=5')
    if status == 200:
        for item in listing['items']:
            if marker in (item.get('title') or ''):
                lead_id = item['id']
                break
    if lead_id:
        break
    time.sleep(1)

if not lead_id:
    print('   FAIL: no lead after 45s — check the worker and `GET /api/v1/jobs`', flush=True)
    status, jobs = call('GET', '/api/v1/jobs?per_page=5')
    for job in (jobs or {}).get('items', []):
        print(f"     job {job['kind']}: {job['status']} {(job['last_error'] or '')[:160]}")
    raise SystemExit(1)

status, detail = call('GET', f'/api/v1/opportunities/{lead_id}')
decision = detail.get('decision') or {}
print(f"   lead: {lead_id}")
print(f"   score={detail.get('score')} ({detail.get('score_category')}) qualification={detail.get('qualification_status')} language={detail.get('language')}")
print(f"   decision: {decision.get('provider')} {decision.get('model')} | tokens {decision.get('input_tokens')}/{decision.get('output_tokens')} | latency {decision.get('latency_ms')} ms")
print()
print("Open the opportunity:")
print(f"  {frontend}/opportunities/{lead_id}")
print("Then click 'Draft three comment variants' (that is the Qwen call) and review them at:")
print(f"  {frontend}/review")
PY
