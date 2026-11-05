#!/usr/bin/env python3
"""Checks scripts/apify-community-sweep.py --scheduled against a stub API.

The nightly job spends money unattended, so the properties that matter are asserted here without any
network: only enabled *and* validated communities are swept, the first cost-guard refusal stops the pass
instead of being retried, re-ingestion touches only succeeded datasets inside the window, and every run
prints exactly one JSON line.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import threading
import urllib.request
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
SCRIPT = ROOT_DIR / "scripts" / "apify-community-sweep.py"
ACTOR_ID = "9sHOY9RzPYGjmTHo8"

failures = 0


def check(name: str, expected, actual) -> None:
    global failures
    if expected == actual:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name}: expected [{expected}] got [{actual}]", file=sys.stderr)
        failures += 1


def iso(days_ago: float) -> str:
    return (datetime.now(timezone.utc) - timedelta(days=days_ago)).isoformat().replace("+00:00", "Z")


class Stub:
    """Minimal Apify/Lead Radar surface, with the refusals the cost guard produces in production."""

    POOL = [
        ("recruiting", "hr_recruiting"),
        ("callcentres", "customer_support"),
        ("customersuccess", "customer_support"),
    ]

    def __init__(self, mode: str, validated: int = 2) -> None:
        self.mode = mode
        self.validated = validated
        self.patches: list[dict] = []
        self.run_posts: list[dict] = []
        self.reingests: list[str] = []
        self.started: list[str] = []
        stub = self

        class Handler(BaseHTTPRequestHandler):
            def _send(self, status: int, payload) -> None:
                body = json.dumps(payload).encode()
                self.send_response(status)
                self.send_header("content-type", "application/json")
                self.send_header("content-length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_GET(self) -> None:  # noqa: N802
                path = self.path.split("?")[0]
                if path == "/api/v1/communities":
                    items = [
                        {
                            "id": f"c{index}",
                            "name": name,
                            "vertical": vertical,
                            "enabled": True,
                            "validation_status": "validated",
                        }
                        for index, (name, vertical) in enumerate(stub.POOL[: stub.validated], 1)
                    ]
                    items += [
                        {
                            "id": "c-pending",
                            "name": "pending-one",
                            "vertical": "customer_support",
                            "enabled": True,
                            "validation_status": "pending",
                        },
                        {
                            "id": "c-disabled",
                            "name": "disabled-one",
                            "vertical": "customer_support",
                            "enabled": False,
                            "validation_status": "validated",
                        },
                    ]
                    self._send(
                        200,
                        {"items": items, "page": 1, "per_page": 100, "total": len(items)},
                    )
                    return
                if path == "/api/v1/providers/apify/actors" and stub.mode == "actors-down":
                    self._send(503, {"error": {"code": "unavailable"}})
                    return
                if path == "/api/v1/providers/apify/actors":
                    self._send(
                        200,
                        {
                            "items": [
                                {
                                    "id": "reg-1",
                                    "actor_id": ACTOR_ID,
                                    "name": "reddit-scraper",
                                    "enabled": True,
                                    "validation_status": "validated",
                                    "max_items_per_run": 50,
                                    "input_template": {"searchTerms": ["\"translation\""]},
                                }
                            ],
                            "page": 1,
                            "per_page": 50,
                            "total": 1,
                        },
                    )
                    return
                if path == "/api/v1/jobs":
                    self._send(200, {"items": [], "page": 1, "per_page": 100, "total": 0})
                    return
                if path == "/api/v1/providers/apify/usage":
                    self._send(
                        200,
                        {
                            "runs_total": 0,
                            "results_total": 0,
                            "known_actual_usd": 0.0,
                            "errors_total": 0,
                        },
                    )
                    return
                if path == "/api/v1/opportunities":
                    self._send(200, {"items": [], "page": 1, "per_page": 50, "total": 0})
                    return
                if path == "/api/v1/providers/apify/runs":
                    runs = [
                        {
                            "id": run_id,
                            "status": "running" if stub.mode == "never-terminal" else "succeeded",
                            "items_count": 0 if stub.mode == "never-terminal" else 10,
                            "dataset_id": None if stub.mode == "never-terminal" else f"ds-{run_id}",
                            "cost_actual_usd": 0.02,
                            "created_at": iso(0),
                        }
                        for run_id in stub.started
                    ]
                    runs += [
                        {
                            "id": "run-yesterday",
                            "status": "succeeded",
                            "items_count": 8,
                            "dataset_id": "ds-yesterday",
                            "cost_actual_usd": 0.02,
                            "created_at": iso(1),
                        },
                        {
                            "id": "run-3days",
                            "status": "succeeded",
                            "items_count": 5,
                            "dataset_id": "ds-3days",
                            "cost_actual_usd": 0.02,
                            "created_at": iso(3),
                        },
                        {
                            "id": "run-old",
                            "status": "succeeded",
                            "items_count": 8,
                            "dataset_id": "ds-old",
                            "cost_actual_usd": 0.02,
                            "created_at": iso(30),
                        },
                        {
                            "id": "run-failed",
                            "status": "failed",
                            "items_count": 0,
                            "dataset_id": None,
                            "cost_actual_usd": 0.0,
                            "created_at": iso(1),
                        },
                        {
                            "id": "run-empty",
                            "status": "succeeded",
                            "items_count": 0,
                            "dataset_id": "ds-empty",
                            "cost_actual_usd": 0.0,
                            "created_at": iso(1),
                        },
                    ]
                    self._send(200, {"items": runs, "page": 1, "per_page": 100, "total": len(runs)})
                    return
                self._send(404, {"error": {"code": "not_found"}})

            def do_PATCH(self) -> None:  # noqa: N802
                length = int(self.headers.get("content-length", 0))
                body = self.rfile.read(length).decode()
                stub.patches.append({"path": self.path, "body": json.loads(body) if body else None})
                self._send(200, {"id": "reg-1"})

            def do_POST(self) -> None:  # noqa: N802
                length = int(self.headers.get("content-length", 0))
                body = self.rfile.read(length).decode()
                path = self.path.split("?")[0]
                if path.endswith("/reingest"):
                    stub.reingests.append(path.rsplit("/", 2)[-2])
                    self._send(202, {"job_id": "job-reingest"})
                    return
                if path == "/api/v1/jobs":
                    self._send(200, {"items": [], "page": 1, "per_page": 100, "total": 0})
                    return
                if path == "/api/v1/providers/apify/usage":
                    self._send(
                        200,
                        {
                            "runs_total": 0,
                            "results_total": 0,
                            "known_actual_usd": 0.0,
                            "errors_total": 0,
                        },
                    )
                    return
                if path == "/api/v1/opportunities":
                    self._send(200, {"items": [], "page": 1, "per_page": 50, "total": 0})
                    return
                if path == "/api/v1/providers/apify/runs":
                    stub.run_posts.append(json.loads(body) if body else None)
                    refusal = stub.refusal_for(len(stub.run_posts))
                    if refusal:
                        self._send(409, refusal)
                        return
                    run_id = f"run-{len(stub.started) + 1}"
                    stub.started.append(run_id)
                    self._send(202, {"run_id": run_id, "job_id": f"job-{run_id}", "status": "queued"})
                    return
                self._send(404, {"error": {"code": "not_found"}})

            def log_message(self, *args) -> None:
                pass

        self.handler = Handler
        self.server = HTTPServer(("127.0.0.1", 0), Handler)
        self.port = self.server.server_address[1]

    def rejection(self, reason: str) -> dict:
        return {"error": {"code": "cost_guard_rejected", "details": {"reason": reason}}}

    def refusal_for(self, attempt: int):
        if self.mode == "kill":
            return self.rejection("kill_switch")
        if self.mode == "guard" and attempt >= 2:
            return self.rejection("daily_ceiling_reached")
        if self.mode.startswith("guard@"):
            # Refuse from the Nth attempt onwards, to prove no refusal point is retried.
            return self.rejection("daily_ceiling_reached") if attempt >= int(self.mode.split("@")[1]) else None
        return None

    def __enter__(self) -> "Stub":
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        return self

    def __exit__(self, *_) -> None:
        self.server.shutdown()
        self.server.server_close()


def run_scheduled(port: int, *extra: str, token: str = "test-token") -> tuple[int, str, str]:
    command = [
        sys.executable,
        str(SCRIPT),
        "--scheduled",
        "--api-url",
        f"http://127.0.0.1:{port}",
        "--env-file",
        str(Path("/nonexistent")),
        *extra,
    ]
    environment = {k: v for k, v in os.environ.items() if k != "API_TOKEN"}
    if token:
        environment["API_TOKEN"] = token
    process = subprocess.run(command, capture_output=True, text=True, env=environment, timeout=120)
    return process.returncode, process.stdout.strip(), process.stderr.strip()


def summary_of(stdout: str) -> dict:
    lines = [line for line in stdout.splitlines() if line.strip()]
    return json.loads(lines[-1]) if lines else {}


def check_wait_does_not_hide(case: str, stdout: str) -> None:
    lines = [line for line in stdout.splitlines() if line.strip()]
    check(f"{case}: exactly one stdout line", 1, len(lines))


print("apify-community-sweep.py --scheduled")

# 1. A healthy night: only enabled + validated communities, one run each, bounded re-ingestion, one line.
with Stub("ok") as stub:
    code, out, err = run_scheduled(stub.port)
    summary = summary_of(out)
    check("sweep: exit code", 0, code)
    check_wait_does_not_hide("sweep", out)
    check("sweep: one run per validated community", 2, len(stub.run_posts))
    check("sweep: queued count", 2, summary.get("queued"))
    check("sweep: no refusal", 0, summary.get("refused"))
    check("sweep: stopped_reason is null", None, summary.get("stopped_reason"))
    check("sweep: template patched once per community", 2, len(stub.patches))
    patched = [p["body"]["input_template"]["withinCommunity"] for p in stub.patches]
    check("sweep: only the validated communities", ["recruiting", "callcentres"], patched)
    check("sweep: items limit honoured", [{"actor_registry_id": "reg-1", "items_limit": 10}] * 2, stub.run_posts)
    # Two candidates inside the default seven-day window, newest first; the 30-day-old one is out.
    check(
        "sweep: re-ingests the datasets inside the window",
        ["run-yesterday", "run-3days"],
        stub.reingests,
    )
    check("sweep: reingested count", 2, summary.get("reingested"))
    check("sweep: no traceback", "", err)

# 2. A cost-guard refusal stops the night: the second community is never attempted again.
with Stub("guard") as stub:
    code, out, err = run_scheduled(stub.port)
    summary = summary_of(out)
    check("guard: exit code stays 0 (a refusal is a decision, not a crash)", 0, code)
    check_wait_does_not_hide("guard", out)
    check("guard: no retry after the refusal", 2, len(stub.run_posts))
    check("guard: queued", 1, summary.get("queued"))
    check("guard: refused", 1, summary.get("refused"))
    check("guard: stopped_reason", "daily_ceiling_reached", summary.get("stopped_reason"))
    # Re-reading a dataset costs nothing, so the data already paid for is still consumed.
    check(
        "guard: the free re-ingestion still runs",
        ["run-yesterday", "run-3days"],
        stub.reingests,
    )
    check("guard: no traceback", "", err)

# 3. Every refusal point is final: refusing the first, second or third run never retries it.
for attempt in (1, 2, 3):
    with Stub(f"guard@{attempt}", validated=3) as stub:
        code, out, _ = run_scheduled(stub.port)
        summary = summary_of(out)
        # A pass that queued nothing is exit 3; one that queued earlier work is a completed night.
        check(f"refusal at attempt {attempt}: exit code", 3 if attempt == 1 else 0, code)
        check_wait_does_not_hide(f"refusal at attempt {attempt}", out)
        check(f"refusal at attempt {attempt}: no retry", attempt, len(stub.run_posts))
        check(f"refusal at attempt {attempt}: refused", 1, summary.get("refused"))
        expected_queued = attempt - 1
        check(f"refusal at attempt {attempt}: queued", expected_queued, summary.get("queued"))
        check(
            f"refusal at attempt {attempt}: stopped_reason",
            "daily_ceiling_reached",
            summary.get("stopped_reason"),
        )

# 4. The kill switch refuses the very first run and nothing else is attempted.
with Stub("kill") as stub:
    code, out, _ = run_scheduled(stub.port)
    summary = summary_of(out)
    # A night that queued nothing is a failed run, so the platform shows it instead of a silent success.
    check("kill switch: exit code", 3, code)
    check_wait_does_not_hide("kill switch", out)
    check("kill switch: exactly one attempt", 1, len(stub.run_posts))
    check("kill switch: queued", 0, summary.get("queued"))
    check("kill switch: stopped_reason", "kill_switch", summary.get("stopped_reason"))

# 5. The manual mode the operator runs interactively keeps its scoreboard and its filters.
with Stub("ok") as stub:
    process = subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "--api-url",
            f"http://127.0.0.1:{stub.port}",
            "--env-file",
            str(Path("/nonexistent")),
            "--skip",
            "callcentres",
            "--reingest-days",
            "0",
        ],
        capture_output=True,
        text=True,
        env={**os.environ, "API_TOKEN": "test-token"},
        timeout=120,
    )
    output = process.stdout
    check("manual: exit code", 0, process.returncode)
    check("manual: one community after --skip", 1, len(stub.run_posts))
    check("manual: the scoreboard still prints", True, "opportunities: 0" in output)
    check("manual: the sweep header still prints", True, "sweep over 1 communities" in output)
    check("manual: no JSON summary line", False, output.strip().splitlines()[-1].startswith("{"))

# 6. Re-ingestion can be switched off, and the window follows the flag.
with Stub("ok") as stub:
    code, out, _ = run_scheduled(stub.port, "--reingest-days", "0")
    summary = summary_of(out)
    check("no re-ingest: exit code", 0, code)
    check("no re-ingest: nothing queued for re-ingestion", [], stub.reingests)
    check("no re-ingest: report", 0, summary.get("reingested"))

with Stub("ok") as stub:
    code, out, _ = run_scheduled(stub.port, "--reingest-days", "60", "--reingest-limit", "1")
    summary = summary_of(out)
    check("window: exit code", 0, code)
    check("window: the limit keeps the newest candidate", ["run-yesterday"], stub.reingests)
    check("window: report", 1, summary.get("reingested"))

# 6b. --limit-communities is a hard bound, and the pass reports how many it took.
with Stub("ok", validated=3) as stub:
    code, out, _ = run_scheduled(stub.port, "--reingest-days", "0", "--limit-communities", "1")
    summary = summary_of(out)
    check("limit: exit code", 0, code)
    check("limit: one run only", 1, len(stub.run_posts))
    check("limit: communities reported", 1, summary.get("communities"))

# 6c. A failure listing actors still prints the single JSON line.
with Stub("actors-down") as stub:
    code, out, _ = run_scheduled(stub.port)
    summary = summary_of(out)
    check("actor list down: exit code", 1, code)
    check_wait_does_not_hide("actor list down", out)
    check("actor list down: stopped_reason", "actor_list_failed", summary.get("stopped_reason"))

# 6d. A run that never reaches a terminal state stops the night instead of stacking another run.
with Stub("never-terminal") as stub:
    code, out, _ = run_scheduled(
        stub.port, "--reingest-days", "0", "--limit-communities", "2",
        "--wait-seconds", "1", "--poll-seconds", "0.1",
    )
    summary = summary_of(out)
    check("stalled run: exit code", 0, code)
    check("stalled run: only one run posted", 1, len(stub.run_posts))
    check("stalled run: stopped_reason", "run_not_terminal", summary.get("stopped_reason"))

# 6e. A dry run reports itself instead of printing nothing.
with Stub("ok") as stub:
    process = subprocess.run(
        [sys.executable, str(SCRIPT), "--scheduled", "--dry-run",
         "--api-url", f"http://127.0.0.1:{stub.port}", "--env-file", str(Path("/nonexistent"))],
        capture_output=True, text=True, env={**os.environ, "API_TOKEN": "test-token"}, timeout=120,
    )
    summary = summary_of(process.stdout)
    check("dry run: exit code", 0, process.returncode)
    check("dry run: last line is the summary", "dry_run", summary.get("stopped_reason"))

# 7. No token: one JSON line and a non-zero exit, so the platform shows a failed run.
code, out, _ = run_scheduled(1, token="")
summary = summary_of(out)
check("no token: exit code", 1, code)
check_wait_does_not_hide("no token", out)
check("no token: stopped_reason", "token_missing", summary.get("stopped_reason"))

# 8. --dry-run changes nothing on the server.
with Stub("ok") as stub:
    process = subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "--scheduled",
            "--dry-run",
            "--api-url",
            f"http://127.0.0.1:{stub.port}",
            "--env-file",
            str(Path("/nonexistent")),
        ],
        capture_output=True,
        text=True,
        env={**os.environ, "API_TOKEN": "test-token"},
        timeout=120,
    )
    check("dry run: exit code", 0, process.returncode)
    check("dry run: no run queued", 0, len(stub.run_posts))
    check("dry run: no template patched", 0, len(stub.patches))

if failures:
    print(f"apify-community-sweep.py: {failures} failure(s)", file=sys.stderr)
    raise SystemExit(1)
print("apify-community-sweep.py: all checks passed")
