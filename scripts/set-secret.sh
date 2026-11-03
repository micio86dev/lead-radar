#!/usr/bin/env bash
# Store one provider secret in .env without echoing it and without leaving it in shell history.
#
#   ./scripts/set-secret.sh JEV_API_KEY
#
# The value is read with a hidden prompt, checked for whitespace/control characters and written; an
# unusual prefix is reported as WARN but does not block, because several deployments speak the same
# protocol with different key families (for example `sk-glm5-` on jev-ai.org and `apikey_` on
# api.typesafe.ai). Nothing is printed except PASS/WARN/FAIL.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${LEAD_RADAR_ENV_FILE:-$ROOT/.env}"
VAR="${1:-}"

if [[ -z "$VAR" ]]; then
  echo "usage: $0 <VARIABLE_NAME>   (JEV_API_KEY, APIFY_API_TOKEN, QWEN_API_KEY, LAYA_API_KEY)" >&2
  exit 2
fi

# Known key families per variable, used only to warn about a possible mismatch.
case "$VAR" in
  JEV_API_KEY)      KNOWN_PREFIXES='apikey_ sk-glm5-' ;;
  APIFY_API_TOKEN)  KNOWN_PREFIXES='apify_api_' ;;
  LAYA_API_KEY)     KNOWN_PREFIXES='lsk_' ;;
  QWEN_API_KEY)     KNOWN_PREFIXES='sk-' ;;
  *) echo "unknown variable $VAR" >&2; exit 2 ;;
esac

if [[ ! -f "$ENV_FILE" ]]; then
  echo "missing $ENV_FILE (copy .env.example first)" >&2
  exit 1
fi

printf 'Paste %s (input hidden), then press Enter: ' "$VAR" >&2
IFS= read -rs VALUE || true
printf '\n' >&2

export LEAD_RADAR_SECRET_VALUE="$VALUE" LEAD_RADAR_SECRET_VAR="$VAR" \
       LEAD_RADAR_SECRET_PREFIXES="$KNOWN_PREFIXES" LEAD_RADAR_SECRET_FILE="$ENV_FILE"

python3 - <<'PY'
import os
from pathlib import Path

value = os.environ.pop('LEAD_RADAR_SECRET_VALUE', '')
name = os.environ.pop('LEAD_RADAR_SECRET_VAR', '')
prefixes = os.environ.pop('LEAD_RADAR_SECRET_PREFIXES', '').split()
path = Path(os.environ.pop('LEAD_RADAR_SECRET_FILE', ''))

value = value.strip().strip('"').strip("'")

problems = []
if not value:
    problems.append('empty value')
if any(character.isspace() or not character.isprintable() for character in value):
    problems.append('contains whitespace or control characters')
if len(value) < 20:
    problems.append(f'unusually short ({len(value)} characters)')

if problems:
    for problem in problems:
        print(f'FAIL: {problem}', flush=True)
    raise SystemExit(1)

if prefixes and not any(value.startswith(prefix) for prefix in prefixes):
    print(
        f'WARN: prefix is not one of {prefixes}; check that the key belongs to the base URL '
        f'configured for {name} (the provider probe will confirm it)',
        flush=True,
    )

lines = path.read_text().splitlines()
written = False
for index, line in enumerate(lines):
    if line.strip().startswith(f'{name}='):
        lines[index] = f'{name}={value}'
        written = True
if not written:
    lines.append(f'{name}={value}')
path.write_text('\n'.join(lines) + '\n')

marker = 'WARN' if prefixes and not any(value.startswith(prefix) for prefix in prefixes) else 'PASS'
print(f'{marker}: {name} written to {path.name} ({len(value)} characters)', flush=True)
PY

echo "Restart the stack so containers read the new value: docker compose up -d --force-recreate api worker frontend" >&2
