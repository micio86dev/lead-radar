#!/usr/bin/env bash
# Diagnose Reddit Data API credentials without exposing them.
#
#   ./scripts/reddit-token-check.sh
#
# Prompts for the app's client id (visible) and secret (hidden), requests an app-only OAuth token from
# the documented endpoint, then performs one search call against oauth.reddit.com. It prints only
# statuses, scopes, expiry, rate-limit headers and the number of items returned: never the secret or
# the token. Every step is documented in docs/reddit-official-api.md.
set -euo pipefail

TOKEN_URL="https://www.reddit.com/api/v1/access_token"
API_HOST="https://oauth.reddit.com"

printf 'Reddit app client id (visible, not a secret): '
IFS= read -r CLIENT_ID || true
printf 'Reddit app secret (hidden): '
IFS= read -rs CLIENT_SECRET || true
printf '\n'
printf 'User-Agent (format "platform:app-id:version (by /u/username)"): '
IFS= read -r USER_AGENT || true
printf 'Optional: reddit username for the password grant (empty to use app-only): '
IFS= read -r REDDIT_USER || true
if [[ -n "$REDDIT_USER" ]]; then
  printf 'Reddit password for %s (hidden): ' "$REDDIT_USER"
  IFS= read -rs REDDIT_PASS || true
  printf '\n'
fi

if [[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" ]]; then
  echo "FAIL: client id and secret are required" >&2
  exit 1
fi
if [[ -z "$USER_AGENT" ]]; then
  echo "FAIL: Reddit requires a unique, descriptive User-Agent; generic ones are throttled" >&2
  exit 1
fi

export REDDIT_CLIENT_ID="$CLIENT_ID" REDDIT_CLIENT_SECRET="$CLIENT_SECRET" \
       REDDIT_USER_AGENT="$USER_AGENT" REDDIT_USER="$REDDIT_USER" \
       REDDIT_PASS="$REDDIT_PASS" TOKEN_URL="$TOKEN_URL" API_HOST="$API_HOST"

python3 - <<'PY'
import base64, json, os, urllib.error, urllib.parse, urllib.request

client_id = os.environ['REDDIT_CLIENT_ID']
client_secret = os.environ['REDDIT_CLIENT_SECRET']
user_agent = os.environ['REDDIT_USER_AGENT']
username = os.environ.get('REDDIT_USER', '')
password = os.environ.get('REDDIT_PASS', '')

if username:
    form = {'grant_type': 'password', 'username': username, 'password': password}
    grant = 'password (script app)'
else:
    form = {'grant_type': 'client_credentials'}
    grant = 'client_credentials (app-only)'

basic = base64.b64encode(f'{client_id}:{client_secret}'.encode()).decode()
request = urllib.request.Request(
    os.environ['TOKEN_URL'],
    data=urllib.parse.urlencode(form).encode(),
    method='POST',
    headers={
        'authorization': f'Basic {basic}',
        'content-type': 'application/x-www-form-urlencoded',
        'user-agent': user_agent,
    },
)
print(f'== token request: grant={grant}')
try:
    with urllib.request.urlopen(request, timeout=30) as response:
        payload = json.load(response)
except urllib.error.HTTPError as error:
    body = error.read().decode(errors='replace')[:300]
    print(f'   HTTP {error.code}: {body}')
    print('   Hints: 401 = wrong client id/secret; unsupported_grant_type = wrong content type or '
          'grant; invalid_grant = wrong username/password or 2FA enabled on the account.')
    raise SystemExit(1)
except Exception as error:
    print(f'   transport error: {type(error).__name__}: {error}')
    raise SystemExit(1)

token = payload.get('access_token')
print('   access_token present:', bool(token))
print('   token_type:', payload.get('token_type'), '| expires_in:', payload.get('expires_in'), '| scope:', payload.get('scope'))
if not token:
    print('   FAIL: the provider returned no access token')
    raise SystemExit(1)

query = urllib.parse.urlencode({
    'q': '"language barrier"',
    'restrict_sr': 1,
    'sort': 'relevance',
    't': 'year',
    'limit': 5,
    'raw_json': 1,
})
url = f"{os.environ['API_HOST']}/r/recruiting/search?{query}"
search = urllib.request.Request(url, headers={'authorization': f'bearer {token}', 'user-agent': user_agent})
print('\n== search call: ' + url.split('?')[0] + '?q=%22language+barrier%22&restrict_sr=1&sort=relevance&t=year&limit=5')
try:
    with urllib.request.urlopen(search, timeout=30) as response:
        print('   HTTP', response.status)
        for header in ('x-ratelimit-used', 'x-ratelimit-remaining', 'x-ratelimit-reset'):
            if response.headers.get(header):
                print(f'   {header}: {response.headers.get(header)}')
        payload = json.load(response)
except urllib.error.HTTPError as error:
    print(f'   HTTP {error.code}: {error.read().decode(errors="replace")[:300]}')
    print('   Hints: 401 = expired/invalid token; 403 = blocked user agent, missing approval or '
          'restricted content; 429 = rate limit (100 QPM per client id).')
    raise SystemExit(1)

children = (payload.get('data') or {}).get('children') or []
print('   posts returned:', len(children))
for child in children[:5]:
    data = child.get('data') or {}
    print('   -', (data.get('title') or '')[:70], '|', data.get('permalink'))
print('\nRESULT: credentials work. Lead Radar can use this app for authorized discovery.')
PY
