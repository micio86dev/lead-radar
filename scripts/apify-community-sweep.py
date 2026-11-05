#!/usr/bin/env python3
"""Targeted Reddit discovery sweep over enabled communities.

Runs the validated Apify Reddit actor once per community, using quoted phrases per vertical and the
documented `withinCommunity` field, then waits for the pipeline (ingestion -> keyword gate -> decision)
to settle and prints the scoreboard. Apify is billed per run, so every run carries the actor's
provider-side charge cap and the configured item limit.

    ./scripts/apify-community-sweep.py --only CrossLanguageCalls,eventprofs --extra-terms '"interpreter needed"'
    ./scripts/apify-community-sweep.py --skip remotework,callcentres

Unattended mode is what the nightly cron runs:

    ./scripts/apify-community-sweep.py --scheduled

In `--scheduled` mode the sweep stops at the first run the server-side cost guard refuses (kill switch,
daily ceiling, per-run cap, concurrency), never retries a refused run, re-ingests datasets collected in the
recent window (free: no new Apify run) and prints exactly one JSON line for the service log.

Environment: the bearer token comes from API_TOKEN, or from .env (DEV_API_TOKEN / LEAD_RADAR_API_TOKEN) for
manual runs; the Apify token is only needed for dataset inspection and is never printed. Configuration is
read from the API, so the approved communities and the actor are the single source of truth.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

TERMS = {
    "hr_recruiting": ['"language barrier"', '"multilingual"', '"bilingual"', '"interpreter"'],
    "international_meetings": ['"language barrier"', '"translation"', '"multilingual"', '"accent"'],
    "conferences_webinars": ['"interpretation"', '"translation"', '"multilingual"', '"captions"'],
    "customer_support": ['"language barrier"', '"translation"', '"multilingual"'],
    "tourism_hospitality": ['"language barrier"', '"translation"', '"multilingual"'],
}
ACTOR_KEY = "9sHOY9RzPYGjmTHo8"  # harshmaur/reddit-scraper, validated by the operator
TERMINAL = ("succeeded", "failed", "aborted", "timed_out")


def load_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.split(" #")[0].strip().strip('"').strip("'")
    return values


def parse_timestamp(raw: str | None) -> datetime | None:
    if not raw:
        return None
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None


class Client:
    def __init__(self, base: str, token: str) -> None:
        self.base = base.rstrip("/")
        self.token = token

    def call(self, method: str, path: str, body=None, timeout: int = 120):
        data = None if body is None else json.dumps(body).encode()
        request = urllib.request.Request(
            self.base + path,
            data=data,
            method=method,
            headers={"authorization": "Bearer " + self.token, "content-type": "application/json"},
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                raw = response.read().decode()
                return response.status, (json.loads(raw) if raw else None)
        except urllib.error.HTTPError as error:
            raw = error.read().decode()
            try:
                payload = json.loads(raw) if raw else None
            except json.JSONDecodeError:
                payload = {"raw": raw[:200]}
            return error.code, payload
        except urllib.error.URLError as error:
            return 0, {"error": {"code": "unreachable", "message": str(error.reason)}}


def refusal_reason(payload) -> str:
    """The guard reason the API reports, or the error code when it is a different refusal."""
    error = (payload or {}).get("error") or {}
    details = error.get("details") or {}
    return str(details.get("reason") or error.get("code") or "refused")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--api-url",
        default=os.environ.get("API_BASE") or os.environ.get("LEAD_RADAR_API_URL", "http://localhost:8080"),
    )
    parser.add_argument("--env-file", default=str(Path(__file__).resolve().parent.parent / ".env"))
    parser.add_argument("--only", default="", help="comma separated community names to sweep")
    parser.add_argument("--skip", default="", help="comma separated community names to skip")
    parser.add_argument("--items", type=int, default=10, help="items per run (the actor minimum is 10)")
    parser.add_argument("--cap-usd", type=float, default=0.25, help="provider-side charge cap per run")
    parser.add_argument("--extra-terms", default="", help="comma separated extra quoted phrases")
    parser.add_argument(
        "--actor-id",
        default=os.environ.get("APIFY_SWEEP_ACTOR_ID", ACTOR_KEY),
        help="Apify actor id to run (the registry record must be enabled and validated)",
    )
    parser.add_argument(
        "--limit-communities",
        type=int,
        default=int(os.environ.get("APIFY_SWEEP_COMMUNITIES", "0")),
        help="sweep at most N communities (0 = every enabled and validated community)",
    )
    parser.add_argument(
        "--scheduled",
        action="store_true",
        help="unattended: stop at the first cost-guard refusal, never retry, print one JSON line",
    )
    parser.add_argument(
        "--reingest-days",
        type=int,
        default=None,
        help="re-ingest datasets from succeeded runs of the last N days (default 7 scheduled, 0 manual)",
    )
    parser.add_argument(
        "--reingest-limit",
        type=int,
        default=10,
        help="at most N datasets re-ingested per pass",
    )
    parser.add_argument("--dry-run", action="store_true", help="print the plan and change nothing")
    args = parser.parse_args()

    reingest_days = args.reingest_days if args.reingest_days is not None else (7 if args.scheduled else 0)

    def finish(code: int, **over) -> int:
        """One JSON line per unattended run, whatever the outcome."""
        data = {
            "queued": 0,
            "refused": 0,
            "reingested": 0,
            "stopped_reason": None,
            "actor": args.actor_id,
            "communities": 0,
        }
        data.update(over)
        if args.scheduled:
            print(json.dumps(data), flush=True)
        return code

    env = load_env(Path(args.env_file))
    token = (
        os.environ.get("API_TOKEN")
        or env.get("DEV_API_TOKEN")
        or env.get("LEAD_RADAR_API_TOKEN")
        or ""
    )
    if not token:
        print("missing API_TOKEN (or DEV_API_TOKEN / LEAD_RADAR_API_TOKEN in .env)", file=sys.stderr)
        return finish(1, stopped_reason="token_missing")
    client = Client(args.api_url, token)

    def call(method: str, path: str, body=None):
        status, payload = client.call(method, path, body)
        if status >= 300 or status == 0:
            raise SystemExit(f"{method} {path} failed: {status} {json.dumps(payload)[:200]}")
        return payload

    status, listing = client.call("GET", "/api/v1/communities?per_page=100")
    if status != 200 or not isinstance(listing, dict):
        print(f"cannot list communities: {status} {listing}", file=sys.stderr)
        return finish(1, stopped_reason="community_list_failed")
    only = {name.strip() for name in args.only.split(",") if name.strip()}
    skip = {name.strip() for name in args.skip.split(",") if name.strip()}
    targets = [
        community
        for community in listing["items"]
        if community["enabled"]
        and community["validation_status"] == "validated"
        and (not only or community["name"] in only)
        and community["name"] not in skip
    ]
    if args.limit_communities > 0:
        targets = targets[: args.limit_communities]
    if not targets:
        print("no community selected")
        return finish(0, stopped_reason="no_communities")

    actors = call("GET", "/api/v1/providers/apify/actors")
    actor = next((a for a in actors["items"] if a["actor_id"] == args.actor_id), None)
    if actor is None:
        print(
            f"actor {args.actor_id} is not registered; register and validate it first",
            file=sys.stderr,
        )
        return finish(1, stopped_reason="actor_not_registered")

    extra = [term.strip() for term in args.extra_terms.split(",") if term.strip()]
    queued: list[dict] = []
    started: set[str] = set()
    refused = 0
    stopped_reason: str | None = None

    def emit(line: str) -> None:
        if not args.scheduled:
            print(line, flush=True)

    if args.dry_run:
        for index, community in enumerate(targets, 1):
            print(f"[{index:2}/{len(targets)}] would sweep {community['name']} (actor {args.actor_id})")
    else:
        emit(f"sweep over {len(targets)} communities (items={args.items}, cap=${args.cap_usd})")

    if not args.dry_run:
        for index, community in enumerate(targets, 1):
            terms = TERMS.get(community["vertical"], ['"translation"', '"multilingual"']) + extra
            template = {
                "searchTerms": terms,
                "withinCommunity": community["name"],
                "searchPosts": True,
                "searchComments": False,
                "searchCommunities": False,
                "searchSort": "relevance",
                "searchTime": "year",
                "includeNSFW": False,
                "crawlCommentsPerPost": False,
                "maxPostsCount": args.items,
                "maxCommentsCount": 0,
            }
            status, patch = client.call(
                "PATCH", f"/api/v1/providers/apify/actors/{actor['id']}", {"input_template": template}
            )
            if status >= 300 or status == 0:
                refused += 1
                reason = refusal_reason(patch)
                emit(f"[{index:2}/{len(targets)}] {community['name']:22} template refused {status} {reason}")
                if args.scheduled:
                    stopped_reason = reason
                    break
                continue
            status, run = client.call(
                "POST",
                "/api/v1/providers/apify/runs",
                {"actor_registry_id": actor["id"], "items_limit": args.items},
            )
            if status != 202:
                refused += 1
                reason = refusal_reason(run)
                emit(f"[{index:2}/{len(targets)}] {community['name']:22} refused {status} {reason}")
                if args.scheduled:
                    # A refusal is a budget or guard decision, not a transient error: stop the night here.
                    stopped_reason = reason
                    break
                continue
            run_id = run["run_id"]
            started.add(run_id)
            queued.append({"run_id": run_id, "community": community["name"]})
            final = None
            for _ in range(60):
                status, runs = client.call("GET", "/api/v1/providers/apify/runs?per_page=30")
                current = next((r for r in runs["items"] if r["id"] == run_id), None) if status == 200 else None
                if current and current["status"] in TERMINAL:
                    final = current
                    break
                time.sleep(4)
            if final is None:
                emit(f"[{index:2}/{len(targets)}] {community['name']:22} timeout")
                continue
            emit(
                f"[{index:2}/{len(targets)}] {community['name']:22} {final['status']:9} "
                f"items={final['items_count']:2} cost={final.get('cost_actual_usd')}"
            )

    reingested: list[str] = []
    if reingest_days > 0:
        cutoff = datetime.now(timezone.utc) - timedelta(days=reingest_days)
        status, runs = client.call("GET", "/api/v1/providers/apify/runs?per_page=100")
        candidates = [
            run
            for run in (runs["items"] if status == 200 else [])
            if run["status"] == "succeeded"
            and run.get("dataset_id")
            and run["items_count"] > 0
            and run["id"] not in started
            and (parse_timestamp(run.get("created_at")) or datetime.min.replace(tzinfo=timezone.utc)) >= cutoff
        ]
        candidates.sort(key=lambda run: run.get("created_at") or "", reverse=True)
        for run in candidates[: max(0, args.reingest_limit)]:
            if args.dry_run:
                print(f"would re-ingest dataset of run {run['id']} ({run['items_count']} items)")
                continue
            status, payload = client.call(
                "POST", f"/api/v1/providers/apify/runs/{run['id']}/reingest"
            )
            if status == 202:
                reingested.append(run["id"])
            else:
                emit(f"re-ingest {run['id']} refused {status} {refusal_reason(payload)}")

    if args.dry_run:
        return 0

    if not args.scheduled:
        deadline = time.time() + 600
        while time.time() < deadline:
            jobs = call("GET", "/api/v1/jobs?per_page=100")
            if not [job for job in jobs["items"] if job["status"] in ("queued", "running")]:
                break
            time.sleep(3)

        usage = call("GET", "/api/v1/providers/apify/usage")
        print(
            f"\nApify: runs={usage['runs_total']} results={usage['results_total']} "
            f"usd={round(usage['known_actual_usd'] or 0, 3)} errors={usage['errors_total']}"
        )
        opportunities = call("GET", "/api/v1/opportunities?per_page=50&sort=score&order=desc")
        print(f"opportunities: {opportunities['total']}")
        for item in opportunities["items"][:20]:
            title = (item["title"] or "-")[:50]
            print(
                f"  {item['score'] if item['score'] is not None else '-':>3} "
                f"{item['score_category'] or '-':9} {item['qualification_status']:12} "
                f"{item['community'] or '-':22} {title}"
            )
        return 0 if queued else 1

    return finish(
        0 if args.scheduled or queued else 1,
        queued=len(queued),
        refused=refused,
        reingested=len(reingested),
        stopped_reason=stopped_reason,
        communities=len(targets),
    )


if __name__ == "__main__":
    raise SystemExit(main())
