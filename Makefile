SHELL := /bin/bash
BACKEND := lead-radar-backend
FRONTEND := lead-radar-frontend
COMPOSE := docker compose
COMPOSE_TEST := docker compose -f docker-compose.test.yml
PY := python3

.PHONY: help up down logs ps build migrate seed rescore reset-db test test-backend test-frontend \
        test-e2e test-scripts lint fmt dev-api dev-worker dev-frontend check-env deploy-backend \
        deploy-frontend prepare-queue nightly-import nightly-import-show

help:
	@echo "Lead Radar targets:"
	@echo "  make up            start api + worker + frontend (docker compose)"
	@echo "  make down          stop the stack (keeps the data volume)"
	@echo "  make logs          follow logs"
	@echo "  make migrate       run database migrations"
	@echo "  make seed          run idempotent seeds"
	@echo "  make rescore       recompute scores/qualification from stored decisions (no AI spend)"
	@echo "  make reset-db      DESTRUCTIVE: delete the SQLite volume"
	@echo "  make test          backend + frontend tests"
	@echo "  make test-backend  cargo test + clippy"
	@echo "  make test-frontend bun typecheck + unit tests"
	@echo "  make test-e2e      Playwright end-to-end"
	@echo "  make lint          fmt check + clippy + prettier check + typecheck"
	@echo "  make fmt           format backend and frontend"
	@echo "  make deploy-backend   deploy the committed backend tree to Railway"
	@echo "  make deploy-frontend  deploy the committed frontend tree to Railway"
	@echo "  make nightly-import   run the nightly Apify sweep (billable) once, now"
	@echo "  make nightly-import-show  print what the nightly sweep would do"
	@echo "  make dev-api       run the API locally (needs .env)"
	@echo "  make dev-worker    run the worker locally (needs .env)"
	@echo "  make dev-frontend  run the Astro dev server"

check-env:
	@test -f .env || (echo "missing .env: cp .env.example .env" && exit 1)

up: check-env
	$(COMPOSE) up --build -d
	@echo "frontend: http://localhost:$${FRONTEND_PORT:-4321}  api: http://localhost:$${APP_PORT:-8080}"

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f --tail=200

ps:
	$(COMPOSE) ps

build:
	$(COMPOSE) build

migrate: check-env
	$(COMPOSE) run --rm api /usr/local/bin/db migrate

seed: check-env
	$(COMPOSE) run --rm api /usr/local/bin/db seed

rescore: check-env
	$(COMPOSE) run --rm api /usr/local/bin/db rescore

reset-db:
	@echo "This deletes the Lead Radar SQLite volume. Ctrl-C to abort."
	@sleep 3
	$(COMPOSE) down -v
	@echo "data volume removed"

cron-install:
	@scripts/install-cron.sh install

cron-status:
	@scripts/install-cron.sh status

cron-run:
	@scripts/install-cron.sh run-now

cron-uninstall:
	@scripts/install-cron.sh uninstall

prepare-queue:
	@LOG_FILE=logs/prepare-queue.log scripts/prepare-queue.sh

# The nightly import the platform cron runs at 00:00 UTC. `--dry-run` first: the sweep starts billable
# Apify runs against whatever API_BASE points at, and the cost guard is the only ceiling.
nightly-import-show:
	@scripts/apify-community-sweep.py --scheduled --dry-run

nightly-import:
	@scripts/apify-community-sweep.py --scheduled

test: test-backend test-frontend test-scripts

test-scripts:
	@scripts/test-prepare-queue.sh
	@python3 scripts/test-apify-nightly.py

test-backend:
	cd $(BACKEND) && cargo test --all-targets

test-frontend:
	cd $(FRONTEND) && bun run typecheck && bun run lint && bun run test

test-e2e:
	cd $(FRONTEND) && bun run test:e2e

lint:
	cd $(BACKEND) && cargo fmt --all -- --check && cargo clippy --all-targets -- -D warnings
	cd $(FRONTEND) && bun run typecheck && bun run lint

fmt:
	cd $(BACKEND) && cargo fmt --all
	cd $(FRONTEND) && bun run format

dev-api: check-env
	cd $(BACKEND) && cargo run --bin api

dev-worker: check-env
	cd $(BACKEND) && cargo run --bin worker

dev-frontend:
	cd $(FRONTEND) && bun run dev

# Deploys go through scripts/deploy-railway.sh: it exports the committed tree and refuses to ship
# uncommitted or unpushed work. See docs/deploy-railway.md for why `railway up` from a submodule does
# not work.
deploy-backend:
	@scripts/deploy-railway.sh backend

deploy-frontend:
	@scripts/deploy-railway.sh frontend
