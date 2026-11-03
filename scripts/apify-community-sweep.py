#!/usr/bin/env python3
"""Targeted Reddit discovery sweep over enabled communities.

Runs the validated Apify Reddit actor once per community, using quoted phrases per vertical and the
documented `withinCommunity` field, then waits for the pipeline (ingestion -> keyword gate -> decision)
to settle and prints the scoreboard. Apify is billed per run, so every run carries the actor's
provider-side charge cap and the configured item limit.

    ./scripts/apify-community-sweep.py --only CrossLanguageCalls,eventprofs --extra-terms '"interpreter needed"'
    ./scripts/apify-community-sweep.py --skip remotework,callcentres

Environment: the bearer token is read from .env (DEV_API_TOKEN / LEAD_RADAR_API_TOKEN); the Apify token
is only needed for dataset inspection and is never printed. Configuration is read from the API, so the
approved communities and the actor are the single source of truth.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

TERMS = {
    "hr_recruiting": ['"language barrier"', '"multilingual"', '"bilingual"', '"interpreter"'],
    "international_meetings": ['"language barrier"', '"translation"', '"multilingual"', '"accent"'],
    "conferences_webinars": ['"interpretation"', '"translation"', '"multilingual"', '"captions"'],
    "customer_support": ['"language barrier"', '"translation"', '"multilingual"'],
    "tourism_hospitality": ['"language barrier"', '"translation"', '"multilingual"'],
}
ACTOR_KEY = "9sHOY9RzPYGjmTHo8"  # harshmaur/reddit-scraper, validated by the operator


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
            return error.code, (json.loads(raw) if raw else None)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--api-url", default=os.environ.get("LEAD_RADAR_API_URL", "http://localhost:8080"))
    parser.add_argument("--env-file", default=str(Path(__file__).resolve().parent.parent / ".env"))
    parser.add_argument("--only", default="", help="comma separated community names to sweep")
    parser.add_argument("--skip", default="", help="comma separated community names to skip")
    parser.add_argument("--items", type=int, default=10, help="items per run (the actor minimum is 10)")
    parser.add_argument("--cap-usd", type=float, default=0.25, help="provider-side charge cap per run")
    parser.add_argument("--extra-terms", default="", help="comma separated extra quoted phrases")
    args = parser.parse_args()

    env = load_env(Path(args.env_file))
    token = env.get("DEV_API_TOKEN") or env.get("LEAD_RADAR_API_TOKEN") or ""
    if not token:
        print("missing DEV_API_TOKEN / LEAD_RADAR_API_TOKEN in .env", file=sys.stderr)
        return 1
    client = Client(args.api_url, token)

    def call(method: str, path: str, body=None):
        status, payload = client.call(method, path, body)
        if status >= 300:
            raise SystemExit(f"{method} {path} failed: {status} {json.dumps(payload)[:200]}")
        return payload

    status, listing = client.call("GET", "/api/v1/communities?per_page=100")
    if status != 200 or not isinstance(listing, dict):
        print(f"cannot list communities: {status} {listing}", file=sys.stderr)
        return 1
    only = {name.strip() for name in args.only.split(",") if name.strip()}
    skip = {name.strip() for name in args.skip.split(",") if name.strip()}
    targets = [
        community
        for community in listing["items"]
        if community["enabled"] and (not only or community["name"] in only) and community["name"] not in skip
    ]
    if not targets:
        print("no community selected")
        return 0

    actors = call("GET", "/api/v1/providers/apify/actors")
    actor = next((a for a in actors["items"] if a["actor_id"] == ACTOR_KEY), None)
    if actor is None:
        print(f"actor {ACTOR_KEY} is not registered; register and validate it first", file=sys.stderr)
        return 1

    extra = [term.strip() for term in args.extra_terms.split(",") if term.strip()]
    print(f"sweep over {len(targets)} communities (items={args.items}, cap=${args.cap_usd})", flush=True)
    processed = 0
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
        call("PATCH", f"/api/v1/providers/apify/actors/{actor['id']}", {"input_template": template})
        status, run = client.call(
            "POST",
            "/api/v1/providers/apify/runs",
            {"actor_registry_id": actor["id"], "items_limit": args.items},
        )
        if status != 202:
            reason = ((run or {}).get("error") or {}).get("details") or {}
            print(f"[{index:2}/{len(targets)}] {community['name']:22} refused {status} {reason}", flush=True)
            continue
        run_id = run["run_id"]
        final = None
        for _ in range(60):
            status, runs = client.call("GET", "/api/v1/providers/apify/runs?per_page=30")
            current = next((r for r in runs["items"] if r["id"] == run_id), None) if status == 200 else None
            if current and current["status"] in ("succeeded", "failed", "aborted", "timed_out"):
                final = current
                break
            time.sleep(4)
        if final is None:
            print(f"[{index:2}/{len(targets)}] {community['name']:22} timeout", flush=True)
            continue
        processed += 1
        print(
            f"[{index:2}/{len(targets)}] {community['name']:22} {final['status']:9} "
            f"items={final['items_count']:2} cost={final['cost_actual_usd']}",
            flush=True,
        )

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
    return 0 if processed else 1


if __name__ == "__main__":
    raise SystemExit(main())
