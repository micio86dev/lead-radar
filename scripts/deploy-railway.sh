#!/usr/bin/env bash
# Deploy one service to Railway from exactly the committed tree.
#
# Why this script exists: `railway up` resolves the upload root through Git, and a submodule's `.git`
# is a file, so running it inside `lead-radar-frontend` or `lead-radar-backend` uploads the *parent*
# repository. Railpack then analyzes the wrong tree, ignores the submodule's `railway.json`, and the
# build fails before it starts (twice, on 2026-11-04). This script removes the guesswork:
#
#   1. it exports `git archive HEAD` of the service's repository into a scratch directory, so the
#      upload contains exactly what is committed and pushed;
#   2. it refuses to deploy a repository with uncommitted changes or commits that are not pushed,
#      because "deploys from HEAD" is only true if HEAD is what the remote has;
#   3. it links that scratch directory to the project, environment and service explicitly;
#   4. it runs `railway up --ci` there and cleans up.
#
#   scripts/deploy-railway.sh backend
#   scripts/deploy-railway.sh frontend
#   scripts/deploy-railway.sh cron
#
# Environment: RAILWAY_PROJECT_ID and RAILWAY_ENVIRONMENT default to this project's production ids.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ID="${RAILWAY_PROJECT_ID:-9cf46c11-baf3-4e3f-a9d3-8aa3cb5b5fad}"
ENVIRONMENT="${RAILWAY_ENVIRONMENT:-production}"

usage() {
  sed -n '2,20p' "$0"
  exit 2
}

[ $# -eq 1 ] || usage

case "$1" in
  backend) SERVICE="backend"; REPO_DIR="$ROOT_DIR/lead-radar-backend" ;;
  frontend) SERVICE="frontend"; REPO_DIR="$ROOT_DIR/lead-radar-frontend" ;;
  cron) SERVICE="lead-radar-cron"; REPO_DIR="$ROOT_DIR" ;;
  *) usage ;;
esac

command -v railway >/dev/null || { echo "railway CLI not found in PATH" >&2; exit 3; }
[ -d "$REPO_DIR" ] || { echo "missing repository: $REPO_DIR" >&2; exit 3; }

# A deploy must equal what the remote has, or "deployed from HEAD" means nothing.
if [ -n "$(git -C "$REPO_DIR" status --porcelain)" ]; then
  echo "refusing to deploy $SERVICE: $REPO_DIR has uncommitted changes" >&2
  git -C "$REPO_DIR" status --short >&2
  exit 4
fi
BRANCH="$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)"
if git -C "$REPO_DIR" rev-parse --abbrev-ref "@{upstream}" >/dev/null 2>&1; then
  AHEAD="$(git -C "$REPO_DIR" rev-list --count "@{upstream}..HEAD")"
  if [ "$AHEAD" != "0" ]; then
    echo "refusing to deploy $SERVICE: $AHEAD commit(s) on $BRANCH are not pushed" >&2
    exit 4
  fi
else
  echo "warning: $BRANCH has no upstream; the deploy is local-only ($SERVICE)" >&2
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lead-radar-deploy-XXXXXX")"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

git -C "$REPO_DIR" archive HEAD | tar -x -C "$WORK_DIR"

for required in Dockerfile railway.json; do
  [ -f "$WORK_DIR/$required" ] || {
    echo "refusing to deploy $SERVICE: $required missing from the exported tree" >&2
    exit 5
  }
done

echo "deploying $SERVICE from $REPO_DIR ($BRANCH @ $(git -C "$REPO_DIR" rev-parse --short HEAD))"
(
  cd "$WORK_DIR"
  railway link -p "$PROJECT_ID" -e "$ENVIRONMENT" -s "$SERVICE" >/dev/null
  railway up --ci -s "$SERVICE" -y
)
