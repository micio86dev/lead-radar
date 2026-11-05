#!/usr/bin/env bash
# Chooses which scheduled job this cron container runs. One image, two services:
#
#   CRON_MODE=prepare  (default) refill the reply queue; hourly on Railway
#   CRON_MODE=nightly            import new opportunities; 00:00 UTC on Railway
#
# The nightly mode spends money unattended, so it is bounded three ways: the communities come from the API
# (enabled and validated only), every run passes the server-side cost guard, and the first refusal stops the
# pass. Nothing is retried.
#
# Nightly knobs (all optional):
#   NIGHTLY_ITEMS              items per run (default 10; the operator's actor minimum)
#   NIGHTLY_REINGEST_DAYS      re-ingest datasets from the last N days (default 7, 0 disables)
#   NIGHTLY_REINGEST_LIMIT     at most N datasets per pass (default 10)
#   NIGHTLY_ONLY / NIGHTLY_SKIP  comma separated community allow/deny lists
set -euo pipefail

BIN_DIR="${CRON_BIN_DIR:-/usr/local/bin}"

case "${CRON_MODE:-prepare}" in
  prepare)
    exec "${BIN_DIR}/prepare-queue.sh" "$@"
    ;;
  nightly)
    args=(--scheduled
      --items "${NIGHTLY_ITEMS:-10}"
      --reingest-days "${NIGHTLY_REINGEST_DAYS:-7}"
      --reingest-limit "${NIGHTLY_REINGEST_LIMIT:-10}")
    [ -n "${NIGHTLY_ONLY:-}" ] && args+=(--only "${NIGHTLY_ONLY}")
    [ -n "${NIGHTLY_SKIP:-}" ] && args+=(--skip "${NIGHTLY_SKIP}")
    exec python3 "${BIN_DIR}/apify-community-sweep.py" "${args[@]}"
    ;;
  *)
    echo "cron-entrypoint: unknown CRON_MODE ${CRON_MODE:?}" >&2
    exit 2
    ;;
esac
