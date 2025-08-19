#!/usr/bin/env bash
set -euo pipefail

# ------------ config ------------
DEFAULT_BRANCH_DEV="main"
DEFAULT_BRANCH_STAGING="development"
DEFAULT_BRANCH_PROD="main"

# domain defaults
DEFAULT_DOMAIN_DEV="dev.local.test"
DEFAULT_DOMAIN_STAGING="staging.local.test"
DEFAULT_DOMAIN_PROD="local.test"

HEALTH_URL_DEV="${HEALTH_URL_DEV:-http://localhost:8080/health}"
HEALTH_URL_STAGING="${HEALTH_URL_STAGING:-http://localhost:8080/health}"
HEALTH_URL_PROD="${HEALTH_URL_PROD:-http://localhost/health}"

COMPOSE_DEV="compose/docker-compose.dev.yml"
COMPOSE_STAGING="compose/docker-compose.staging.yml"
COMPOSE_PROD="compose/docker-compose.prod.yml"

ENV_DEV_EXAMPLE="env/.env.dev.example"
ENV_STAGING_EXAMPLE="env/.env.staging.example"
ENV_PROD_EXAMPLE="env/.env.prod.example"

ENV_DEV_REAL="env/.env.dev"
ENV_STAGING_REAL="env/.env.staging"
ENV_PROD_REAL="env/.env.prod"
# --------------------------------

usage() {
  cat <<EOF2
Usage: $0 [dev|staging|prod] [--branch BRANCH] [--fresh] [--no-migrate] [--no-build] [--domain-base DOMAIN] [--no-hosts] [--no-tls]

Examples:
  $0                   # defaults to dev
  $0 dev --fresh       # drop volumes, rebuild, redeploy
  $0 staging --branch release/next
  $0 prod --no-migrate

Flags:
  --branch       Override git branch (default depends on env)
  --fresh        Down stack with -v (drop volumes) before up
  --no-migrate   Skip doctrine migrations
  --no-build     Do not rebuild images on up
  --domain-base  Override domain base (default depends on env)
  --no-hosts     Do not add /etc/hosts entries
  --no-tls       Skip TLS setup
EOF2
}

# args
ENVIRONMENT="${1:-dev}"; shift || true
BRANCH_OVERRIDE=""
FRESH="false"
RUN_MIGRATIONS="true"
REBUILD="true"
DOMAIN_BASE_OVERRIDE=""
ADD_HOSTS="true"
SETUP_TLS="true"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) BRANCH_OVERRIDE="${2:-}"; shift 2 ;;
    --fresh) FRESH="true"; shift ;;
    --no-migrate) RUN_MIGRATIONS="false"; shift ;;
    --no-build) REBUILD="false"; shift ;;
    --domain-base) DOMAIN_BASE_OVERRIDE="${2:-}"; shift 2 ;;
    --no-hosts) ADD_HOSTS="false"; shift ;;
    --no-tls) SETUP_TLS="false"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

# choose branch
case "$ENVIRONMENT" in
  dev)     BRANCH="${BRANCH_OVERRIDE:-$DEFAULT_BRANCH_DEV}" ;;
  staging) BRANCH="${BRANCH_OVERRIDE:-$DEFAULT_BRANCH_STAGING}" ;;
  prod)    BRANCH="${BRANCH_OVERRIDE:-$DEFAULT_BRANCH_PROD}" ;;
  *) echo "Invalid environment: $ENVIRONMENT"; usage; exit 1 ;;
esac

# choose compose file
case "$ENVIRONMENT" in
  dev)     COMPOSE_FILE="$COMPOSE_DEV" ;;
  staging) COMPOSE_FILE="$COMPOSE_STAGING" ;;
  prod)    COMPOSE_FILE="$COMPOSE_PROD" ;;
esac

if [[ ! -f "$COMPOSE_FILE" ]]; then
  if [[ "$ENVIRONMENT" == "staging" && -f "$COMPOSE_PROD" ]]; then
    echo "[warn] $COMPOSE_FILE not found; using $COMPOSE_PROD for staging."
    COMPOSE_FILE="$COMPOSE_PROD"
  else
    echo "[error] Compose file not found: $COMPOSE_FILE"; exit 2
  fi
fi

# choose env files
case "$ENVIRONMENT" in
  dev)     ENV_EXAMPLE="$ENV_DEV_EXAMPLE"; ENV_REAL="$ENV_DEV_REAL" ;;
  staging) ENV_EXAMPLE="$ENV_STAGING_EXAMPLE"; ENV_REAL="$ENV_STAGING_REAL" ;;
  prod)    ENV_EXAMPLE="$ENV_PROD_EXAMPLE"; ENV_REAL="$ENV_PROD_REAL" ;;
esac

# decide domain base
case "$ENVIRONMENT" in
  dev)     DOMAIN_BASE="${DOMAIN_BASE_OVERRIDE:-$DEFAULT_DOMAIN_DEV}" ;;
  staging) DOMAIN_BASE="${DOMAIN_BASE_OVERRIDE:-$DEFAULT_DOMAIN_STAGING}" ;;
  prod)    DOMAIN_BASE="${DOMAIN_BASE_OVERRIDE:-$DEFAULT_DOMAIN_PROD}" ;;
esac
export DOMAIN_BASE

# helper: docker compose vs docker-compose
dc() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    docker compose -f "$COMPOSE_FILE" "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose -f "$COMPOSE_FILE" "$@"
  else
    echo "[error] docker compose not found"; exit 3
  fi
}

# 1) git pull
echo "[info] Pulling latest from branch: $BRANCH"
git fetch origin "$BRANCH"
git checkout "$BRANCH"
git pull --ff-only origin "$BRANCH"

# 2) ensure env examples exist
if [[ ! -f "$ENV_EXAMPLE" ]]; then
  echo "[error] Missing env example for $ENVIRONMENT: $ENV_EXAMPLE"; exit 4
fi

# 3) ensure runtime env exists (not committed)
if [[ ! -f "$ENV_REAL" ]]; then
  echo "[info] Creating $ENV_REAL from $ENV_EXAMPLE"
  cp "$ENV_EXAMPLE" "$ENV_REAL"
fi

# 4) ensure root .env exists for host CLI
if [[ ! -f ".env" ]]; then
  echo "[info] Creating root .env for host CLI (dev defaults)"
  cat > .env <<'EOF3'
APP_ENV=dev
APP_DEBUG=1
APP_SECRET=dev-secret-key-change-me
DATABASE_URL="mysql://app:app@127.0.0.1:3307/app?serverVersion=8.4&charset=utf8mb4"
MAILER_DSN=smtp://127.0.0.1:1025
REDIS_URL=redis://127.0.0.1:6379
EOF3
fi

# TLS setup and hosts
APP_HOST="app.${DOMAIN_BASE}"
ADMINER_HOST="adminer.${DOMAIN_BASE}"
MAILPIT_HOST="mail.${DOMAIN_BASE}"

# TLS setup (mkcert) for dev/staging (skip for prod if you use real certs)
if [[ "$SETUP_TLS" == "true" ]]; then
  if [[ "$ENVIRONMENT" != "prod" ]]; then
    echo "[info] Setting up TLS for ${DOMAIN_BASE}"
    ./scripts/setup-tls.sh "$DOMAIN_BASE"
  else
    echo "[info] Skipping TLS generation in prod mode (expect external certs)."
  fi
fi

# /etc/hosts entries (app + optional helpers)
if [[ "$ADD_HOSTS" == "true" ]]; then
  echo "[info] Adding /etc/hosts entries (requires sudo)"
  add_host() {
    local host="$1"
    if ! grep -qE "^[0-9.]+\s+${host}(\s|$)" /etc/hosts 2>/dev/null; then
      echo "127.0.0.1 ${host}" | sudo tee -a /etc/hosts >/dev/null || true
    fi
  }
  add_host "$APP_HOST"
  add_host "$ADMINER_HOST"
  add_host "$MAILPIT_HOST"
fi

# 5) restart stack
if [[ "$FRESH" == "true" ]]; then
  echo "[info] Bringing stack down (with volumes)"
  dc down -v || true
else
  echo "[info] Bringing stack down"
  dc down || true
fi

echo "[info] Starting stack ($ENVIRONMENT) using $COMPOSE_FILE"
if [[ "$REBUILD" == "true" ]]; then
  dc up -d --build
else
  dc up -d
fi

# 6) wait for DB to become ready (best-effort)
echo "[info] Waiting for DB (up to ~30s)..."
sleep 10
dc logs --tail=100 || true
sleep 10

# 7) composer install (inside php container)
if grep -q "services:" "$COMPOSE_FILE"; then
  echo "[info] Installing Composer deps in php container"
  dc exec php composer install --no-interaction --prefer-dist --optimize-autoloader
fi

# 8) database create + migrations (optional)
if [[ "$RUN_MIGRATIONS" == "true" ]]; then
  echo "[info] Ensuring database exists"
  # Corrected: remove the accidental 'php' after -d
  dc exec php php bin/console doctrine:database:create --if-not-exists --no-interaction || true

  echo "[info] Checking if doctrine:migrations commands are available"
  if dc exec php php bin/console list --raw | grep -q '^doctrine:migrations:migrate'; then
    echo "[info] Running doctrine migrations (will skip if none)"
    # Key flag: don't fail when there are no registered migrations
    dc exec php php bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration || true
  else
    echo "[info] No doctrine:migrations:* commands found. Skipping migrations."
  fi
fi

# 9) health check
case "$ENVIRONMENT" in
  dev)     HEALTH_URL="$HEALTH_URL_DEV" ;;
  staging) HEALTH_URL="$HEALTH_URL_STAGING" ;;
  prod)    HEALTH_URL="$HEALTH_URL_PROD" ;;
esac

echo "[info] Health check: $HEALTH_URL"
if command -v curl >/dev/null 2>&1; then
  curl -fsS "$HEALTH_URL" || true
  echo
else
  echo "[warn] curl not found; skipping health check output"
fi

# URLs summary
APP_HTTPS_URL="https://${APP_HOST}"
APP_HTTP_URL="http://${APP_HOST}"
ADMINER_URL="http://localhost:8081"
MAILPIT_URL="http://localhost:8025"

echo ""
echo "[urls] Environment: $ENVIRONMENT   Domain base: $DOMAIN_BASE"
echo "[urls] App (HTTPS):  ${APP_HTTPS_URL}"
echo "[urls] App (HTTP):   ${APP_HTTP_URL}  (redirects to HTTPS)"
echo "[urls] Adminer:      ${ADMINER_URL}"
echo "[urls] Mailpit:      ${MAILPIT_URL}"

echo "[success] Deployment completed for environment: $ENVIRONMENT"
