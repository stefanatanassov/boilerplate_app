#!/usr/bin/env bash
set -euo pipefail

# ------------ config ------------
DEFAULT_BRANCH_DEV="main"
DEFAULT_BRANCH_STAGING="development"
DEFAULT_BRANCH_PROD="main"

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
Usage: $0 [dev|staging|prod] [--branch BRANCH] [--fresh] [--no-migrate] [--no-build]

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
EOF2
}

# args
ENVIRONMENT="${1:-dev}"; shift || true
BRANCH_OVERRIDE=""
FRESH="false"
RUN_MIGRATIONS="true"
REBUILD="true"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) BRANCH_OVERRIDE="${2:-}"; shift 2 ;;
    --fresh) FRESH="true"; shift ;;
    --no-migrate) RUN_MIGRATIONS="false"; shift ;;
    --no-build) REBUILD="false"; shift ;;
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

echo "[success] Deployment completed for environment: $ENVIRONMENT"
