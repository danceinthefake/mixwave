# mixwave — convenience targets. `make` with no args prints help.
#
# Real source of truth is still `mix.exs` aliases and `package.json`
# scripts; this file just gives the things you type 20 times a day
# short names.

.DEFAULT_GOAL := help
.PHONY: help setup server s iex iex-server \
        node1 node2 \
        test test-js test-watch test-all coverage coverage-js \
        format format-check lint check precommit \
        db-up db-reset psql \
        assets-build assets-clean \
        prod-secret prod-build prod-build-lan prod-db-setup \
        prod-node1 prod-node2 prod-remote \
        deploy logs ssh

# --------------------------------------------------------------------
# Help — self-documents by grepping for `## ...` comments on targets.
# --------------------------------------------------------------------

help: ## Show this help.
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make \033[36m<target>\033[0m\n\nTargets:\n"} \
		/^[a-zA-Z0-9_-]+:.*##/ { printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2 } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

##@ Dev loop

setup: db-up ## First-time setup: deps + db + assets.
	mix setup

server: db-up ## Run the Phoenix dev server (Vite HMR included).
	mix phx.server

s: server ## Alias for `server`.

iex: db-up ## Open an iex session in the project.
	iex -S mix

iex-server: db-up ## iex + Phoenix server in one shell.
	iex -S mix phx.server

##@ Multi-node cluster (two BEAM nodes, one Postgres, one Vite)

node1: db-up ## Terminal 1: primary node (owns Vite).
	PORT=4000 iex --sname mixwave1 --cookie shared -S mix phx.server

node2: db-up ## Terminal 2: peer node (skips Vite, auto-clusters via dns_cluster).
	PORT=4001 SKIP_VITE=1 iex --sname mixwave2 --cookie shared -S mix phx.server

##@ Tests / lint / format

test: db-up ## Run the Elixir test suite.
	mix test

test-js: ## Run the Vue / TS test suite (vitest, one-shot).
	pnpm test

test-watch: ## Vitest in watch mode.
	pnpm test:watch

test-all: test test-js ## Elixir + JS tests, one after the other.

coverage: db-up ## Elixir coverage report (excoveralls).
	mix coveralls.html

coverage-js: ## Vue / TS coverage report.
	pnpm test:coverage

format: ## Apply mix format + oxfmt.
	mix format
	pnpm format

format-check: ## Read-only format check (what CI runs).
	mix format --check-formatted
	pnpm format:check

lint: ## oxlint over the Vue tree.
	pnpm lint

check: format-check lint test-js ## Full JS CI dry run: format-check + lint + tests.

precommit: db-up ## Elixir precommit alias (compile-as-errors + unlock + format + test).
	mix precommit

##@ Database

db-up: ## Start the local Postgres container (mixwave-pg). Creates it on first run.
	@if docker container inspect mixwave-pg >/dev/null 2>&1; then \
		docker start mixwave-pg >/dev/null; \
	else \
		echo "  Creating mixwave-pg container..."; \
		docker run -d --name mixwave-pg \
			-e POSTGRES_PASSWORD=postgres -e POSTGRES_USER=postgres \
			-p 5432:5432 postgres:16-alpine >/dev/null; \
	fi

db-reset: db-up ## Drop + recreate the dev DB.
	mix ecto.reset

psql: db-up ## Open psql inside the mixwave-pg container.
	docker exec -it mixwave-pg psql -U postgres -d mixwave_dev

##@ Assets

assets-build: ## One-shot Vite prod build (clears Vite dev mode — see README).
	mix assets.build

assets-clean: ## Undo a stray assets-build so dev mode works again.
	rm -rf priv/static/.vite priv/static/assets priv/static/server.mjs
	@echo "  Cleaned. Restart phx.server."

##@ Production release on the LAN (two-node cluster)
# These targets build + run a real `mix release` locally, bound to your
# LAN IP so a phone or laptop on the same Wi-Fi can hit it. Two release
# nodes form an Erlang cluster (same cookie, different snames); they
# don't auto-connect — `make prod-remote` and run
# `Node.connect(:'mixwave2@<hostname>')` once.
#
# Override LAN_HOST with your machine's LAN IP. `hostname -I` finds it.
#   make prod-node1 LAN_HOST=192.168.1.42
LAN_HOST     ?= 0.0.0.0
PROD_DB_URL  ?= ecto://postgres:postgres@localhost/mixwave_prod
ADMIN_PW     ?= admin
LAN_ENV_FILE := .env.lan

prod-secret: ## Generate persistent SECRET_KEY_BASE + RELEASE_COOKIE in .env.lan (one-time).
	@if [ -f $(LAN_ENV_FILE) ]; then \
		echo "  $(LAN_ENV_FILE) already exists. Delete it to regenerate."; exit 0; \
	fi; \
	{ echo "SECRET_KEY_BASE=$$(mix phx.gen.secret)"; \
	  echo "RELEASE_COOKIE=$$(mix phx.gen.secret 32)"; } > $(LAN_ENV_FILE); \
	echo "  Wrote $(LAN_ENV_FILE) (gitignored)."

# `mix release` evaluates runtime.exs at build time to bundle it, so
# every env var runtime.exs raises on must be set even for the build.
# These values are throw-away — the real ones come from the env at
# `bin/mixwave start` time, see prod-node1 / prod-node2.
BUILD_ENV = SECRET_KEY_BASE=build-only-secret-key-base-padding-padding-padding-padding-padding \
            DATABASE_URL=ecto://build@build/build \
            ADMIN_PASSWORD=build-only-admin-password

prod-build: $(LAN_ENV_FILE) ## Build the prod release for Fly (force_ssl ON, https URLs).
	rm -rf _build/prod
	MIX_ENV=prod mix deps.get --only prod
	$(BUILD_ENV) MIX_ENV=prod mix assets.deploy
	$(BUILD_ENV) MIX_ENV=prod mix release --overwrite

prod-build-lan: $(LAN_ENV_FILE) ## Build the prod release for LAN testing (force_ssl OFF, http URLs).
	rm -rf _build/prod
	MIX_ENV=prod mix deps.get --only prod
	$(BUILD_ENV) DISABLE_FORCE_SSL=1 MIX_ENV=prod mix assets.deploy
	$(BUILD_ENV) DISABLE_FORCE_SSL=1 MIX_ENV=prod mix release --overwrite

prod-db-setup: db-up ## Create + migrate the prod DB locally (mixwave_prod). Run after prod-build-lan.
	$(BUILD_ENV) DISABLE_FORCE_SSL=1 DATABASE_URL=$(PROD_DB_URL) MIX_ENV=prod mix ecto.create
	$(BUILD_ENV) DISABLE_FORCE_SSL=1 DATABASE_URL=$(PROD_DB_URL) MIX_ENV=prod mix ecto.migrate

prod-node1: $(LAN_ENV_FILE) ## Run prod release node1 on $LAN_HOST:4000 (override LAN_HOST=...).
	@if [ "$(LAN_HOST)" = "0.0.0.0" ]; then \
		echo "  Set LAN_HOST=<your LAN IP>. Run 'hostname -I' to find it."; exit 1; \
	fi
	@set -a; . ./$(LAN_ENV_FILE); set +a; \
	PHX_SERVER=true PORT=4000 \
	PHX_HOST=$(LAN_HOST) PHX_SCHEME=http PHX_URL_PORT=4000 \
	DATABASE_URL=$(PROD_DB_URL) ADMIN_PASSWORD=$(ADMIN_PW) \
	RELEASE_DISTRIBUTION=sname RELEASE_NODE=mixwave1 \
	PEER_NODES=mixwave2@$$(hostname -s) \
	_build/prod/rel/mixwave/bin/mixwave start

prod-node2: $(LAN_ENV_FILE) ## Run prod release node2 on $LAN_HOST:4001 (override LAN_HOST=...).
	@if [ "$(LAN_HOST)" = "0.0.0.0" ]; then \
		echo "  Set LAN_HOST=<your LAN IP>. Run 'hostname -I' to find it."; exit 1; \
	fi
	@set -a; . ./$(LAN_ENV_FILE); set +a; \
	PHX_SERVER=true PORT=4001 \
	PHX_HOST=$(LAN_HOST) PHX_SCHEME=http PHX_URL_PORT=4001 \
	DATABASE_URL=$(PROD_DB_URL) ADMIN_PASSWORD=$(ADMIN_PW) \
	RELEASE_DISTRIBUTION=sname RELEASE_NODE=mixwave2 \
	PEER_NODES=mixwave1@$$(hostname -s) \
	_build/prod/rel/mixwave/bin/mixwave start

prod-remote: $(LAN_ENV_FILE) ## Open a remote shell on node1 (use to Node.connect/1 the cluster).
	@set -a; . ./$(LAN_ENV_FILE); set +a; \
	RELEASE_DISTRIBUTION=sname RELEASE_NODE=mixwave1 \
	_build/prod/rel/mixwave/bin/mixwave remote

# File rule so `make prod-node1` auto-generates the env file if missing.
$(LAN_ENV_FILE):
	@$(MAKE) --no-print-directory prod-secret

##@ Fly.io

deploy: ## fly deploy.
	fly deploy

logs: ## fly logs (tail).
	fly logs

ssh: ## fly ssh console into the running machine.
	fly ssh console
