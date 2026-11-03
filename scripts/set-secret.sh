#!/usr/bin/env bash
# Store one provider secret in .env without echoing it and without leaving it in shell history.
#
#   ./scripts/set-secret.sh JEV_API_KEY
#
# The value is read with a hidden prompt, checked for the documented shape and only then written.
# Nothing is printed except PASS/FAIL, so the secret never reaches a terminal, a log or this repo.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${LEAD_RADAR_ENV_FILE:-$ROOT/.env}"
VAR="${1:-}"

if [[ -z "$VAR" ]]; then
  echo "usage: $0 <VARIABLE_NAME>   (JEV_API_KEY, APIFY_API_TOKEN, QWEN_API_KEY, LAYA_API_KEY)" >&2
  exit 2
fi

case "$VAR" in
  JEV_API_KEY)      EXPECTED_PREFIX='sk-glm5-' ;;
  APIFY_API_TOKEN)  EXPECTED_PREFIX='apify_api_' ;;
  LAYA_API_KEY)     EXPECTED_PREFIX='lsk_' ;;
  QWEN_API_KEY)     EXPECTED_PREFIX='' ;;
  *) echo "unknown variable $VAR" >&2; exit 2 ;;
esac

if [[ ! -f "$ENV_FILE" ]]; then
  echo "missing $ENV_FILE (copy .env.example first)" >&2
  exit 1
fi

printf 'Paste %s (input hidden), then press Enter: ' "$VAR" >&2
IFS= read -rs VALUE
printf '\n' >&2

export LEAD_RADAR_SECRET_VALUE="$VALUE" LEAD_RADAR_SECRET_VAR="$VAR" \
       LEAD_RADAR_SECRET_PREFIX="$EXPECTED_PREFIX" LEAD_RADAR_SECRET_FILE="$ENV_FILE"

python3 - <<'PY'
import os
from pathlib import Path

value = os.environ.pop('LEAD_RADAR_SECRET_VALUE', '')
name = os.environ.pop('LEAD_RADAR_SECRET_VAR', '')
prefix = os.environ.pop('LEAD_RADAR_SECRET_PREFIX', '')
path = Path(os.environ.pop('LEAD_RADAR_SECRET_FILE', ''))

value = value.strip().strip('"').strip("'")

problems = []
if not value:
    problems.append('empty value')
if any(ch.isspace() or not ch.isprintable() for ch in value):
    problems.append('contains whitespace or control characters')
if prefix and not value.startswith(prefix):
    problems.append(f'does not start with the documented prefix {prefix!r}')
if len(value) < 20:
    problems.append(f'unusually short ({len(value)} characters)')

if problems:
    for problem in problems:
        print(f'FAIL: {problem}', flush=True)
    raise SystemExit(1)

lines = path.read_text().splitlines()
written = False
for index, line in enumerate(lines):
    if line.strip().startswith(f'{name}='):
        lines[index] = f'{name}={value}'
        written = True
if not written:
    lines.append(f'{name}={value}')
path.write_text('\n'.join(lines) + '\n')
print(f'PASS: {name} written to {path.name} ({len(value)} characters, prefix ok)', flush=True)
PY

echo "Restart the stack so containers read the new value: docker compose up -d --force-recreate api worker frontend" >&2
