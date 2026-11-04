#!/usr/bin/env bash
# Local hourly preparation for the reply queue.
#
# Two supported schedulers:
#   compose   the `scheduler` service in docker-compose.yml (default when you run the stack in Docker)
#   launchd   a per-user macOS agent, for native `make dev-api` / `make dev-worker` runs
#
# macOS launchd cannot read this project from an external volume (TCC blocks it with "Operation not
# permitted"), so the launchd route installs a small runner under ~/Library/Application Support and keeps
# the API token in ~/.config/lead-radar/api-token (0600). The token is read from .env and never printed.
#
#   scripts/install-cron.sh install [--interval 3600]
#   scripts/install-cron.sh status
#   scripts/install-cron.sh run-now
#   scripts/install-cron.sh uninstall [--purge]   # --purge also removes the stored token
set -euo pipefail

LABEL="dev.leadradar.prepare-queue"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST_TEMPLATE="$ROOT_DIR/deploy/launchd/${LABEL}.plist.template"
RUNNER_TEMPLATE="$ROOT_DIR/deploy/launchd/prepare-queue-dev.sh.template"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
RUNNER="$HOME/Library/Application Support/lead-radar/prepare-queue.sh"
CONFIG_DIR="$HOME/.config/lead-radar"
LOG_DIR="$HOME/Library/Logs/lead-radar"
LOG_FILE="$LOG_DIR/prepare-queue.log"
INTERVAL=3600
UID_NUM="$(id -u)"

usage() { sed -n '2,15p' "$0"; exit 2; }

from_env_file() {
  [ -f "$ROOT_DIR/.env" ] || return 0
  grep -E "^$1=" "$ROOT_DIR/.env" | tail -1 | cut -d= -f2- | sed -e 's/^["'\'']//' -e 's/["'\'']$//'
}

store_token() {
  mkdir -p "$CONFIG_DIR"
  chmod 700 "$CONFIG_DIR"
  local token="${API_TOKEN:-}"
  [ -n "$token" ] || token="$(from_env_file DEV_API_TOKEN)"
  [ -n "$token" ] || token="$(from_env_file BOOTSTRAP_API_TOKEN)"
  if [ -n "$token" ]; then
    (umask 177; printf '%s' "$token" >"$CONFIG_DIR/api-token")
    echo "token stored at $CONFIG_DIR/api-token (0600, length ${#token})"
  elif [ -f "$CONFIG_DIR/api-token" ]; then
    echo "keeping the existing $CONFIG_DIR/api-token"
  else
    echo "no token found in .env: set DEV_API_TOKEN there, or run with API_TOKEN=… in the environment" >&2
    exit 3
  fi
  local base="${API_BASE:-$(from_env_file PUBLIC_API_BASE_URL)}"
  base="${base:-http://localhost:8080}"
  printf '%s' "${base%/}" >"$CONFIG_DIR/api-base"
  chmod 600 "$CONFIG_DIR/api-base"
}

install_launchd() {
  mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR" "$(dirname "$RUNNER")" "$CONFIG_DIR"
  store_token
  sed -e "s|{{HOME}}|$HOME|g" "$RUNNER_TEMPLATE" >"$RUNNER"
  chmod 700 "$RUNNER"
  sed -e "s|{{LABEL}}|${LABEL}|g" \
      -e "s|{{HOME}}|$HOME|g" \
      -e "s|{{RUNNER}}|${RUNNER}|g" \
      -e "s|{{LOG}}|${LOG_FILE}|g" \
      -e "s|{{INTERVAL}}|${INTERVAL}|g" \
      "$PLIST_TEMPLATE" >"$PLIST"
  chmod 600 "$PLIST"
  launchctl bootout "gui/${UID_NUM}/${LABEL}" 2>/dev/null || true
  if launchctl bootstrap "gui/${UID_NUM}" "$PLIST" 2>/dev/null; then
    launchctl enable "gui/${UID_NUM}/${LABEL}" 2>/dev/null || true
  else
    launchctl load -w "$PLIST"
  fi
  echo "installed ${LABEL}: every $((INTERVAL / 60)) minutes"
  echo "  runner: $RUNNER"
  echo "  log:    $LOG_FILE"
  echo "  api:    $(cat "$CONFIG_DIR/api-base")"
}

case "${1:-install}" in
  install)
    shift || true
    while [ $# -gt 0 ]; do
      case "$1" in
        --interval) INTERVAL="$2"; shift 2 ;;
        --compose)
          echo "the compose scheduler needs no install: docker compose up -d scheduler"
          echo "  interval: PREPARE_INTERVAL_SECONDS (default 3600)"
          exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
      esac
    done
    install_launchd
    ;;
  uninstall)
    shift || true
    launchctl bootout "gui/${UID_NUM}/${LABEL}" 2>/dev/null || launchctl unload -w "$PLIST" 2>/dev/null || true
    rm -f "$PLIST" "$RUNNER"
    echo "removed ${LABEL}"
    if [ "${1:-}" = "--purge" ]; then
      rm -f "$CONFIG_DIR/api-token" "$CONFIG_DIR/api-base"
      echo "purged $CONFIG_DIR"
    fi
    ;;
  status)
    if [ -f "$PLIST" ]; then
      echo "plist:  $PLIST"
      launchctl print "gui/${UID_NUM}/${LABEL}" 2>/dev/null | grep -E "state = |last exit code|run interval" | sed 's/^/  /' || echo "  (not loaded in this session)"
    else
      echo "launchd agent not installed"
    fi
    echo "--- compose scheduler ---"
    docker compose ps scheduler --format '{{.Service}} {{.State}}' 2>/dev/null | sed 's/^/  /' || echo "  not running"
    echo "--- last runs ---"
    tail -3 "$LOG_FILE" 2>/dev/null | sed 's/^/  /' || echo "  (no runs yet)"
    ;;
  run-now)
    if [ -f "$PLIST" ]; then
      launchctl kickstart -k "gui/${UID_NUM}/${LABEL}"
      sleep 3
    else
      ( cd "$ROOT_DIR" && API_BASE="$(cat "$CONFIG_DIR/api-base" 2>/dev/null || echo http://localhost:8080)" \
        API_TOKEN="$(cat "$CONFIG_DIR/api-token" 2>/dev/null || true)" \
        LOG_FILE="$ROOT_DIR/logs/prepare-queue.log" "$ROOT_DIR/scripts/prepare-queue.sh" )
    fi
    tail -1 "$LOG_FILE" 2>/dev/null || echo "no log line yet"
    ;;
  *) usage ;;
esac
