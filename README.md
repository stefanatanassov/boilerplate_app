# Boilerplate App (Symfony 7 + Docker)

## Run Locally (Dev)

1) Copy envs (creates an untracked env for docker):
   cp env/.env.dev.example env/.env.dev

2) Start stack:
   make up
   # first run: MySQL may take ~10–20s to initialize

3) Install PHP deps inside the php container:
   make install

4) Check health:
   open http://localhost:8080/health
   # expect: {"status":"ok","env":"dev","db":true}

### Tips
- If you see docker warnings about MYSQL_* being unset, ensure `compose/docker-compose.dev.yml`
  has `env_file: ../env/.env.dev` under both `php` and `db` services.
- If `db:false` persists:
  - Recreate with a clean volume so MySQL initializes with the new creds:
    docker compose -f compose/docker-compose.dev.yml down -v
    docker compose -f compose/docker-compose.dev.yml up -d
  - Watch DB logs:
    docker compose -f compose/docker-compose.dev.yml logs -f db

Services:
- App: http://localhost:8080
- Mailpit: http://localhost:8025
- MySQL: port 3307 (local)

## Quality tooling
- `make stan`
- `make psalm`
- `make cs-fix`

## Production
Use `compose/docker-compose.prod.yml` with `env/.env.prod` (from `env/.env.prod.example`).
Provide DB creds and secure `APP_SECRET`.

## Structure
- `docker/` images for PHP & Nginx
- `compose/` dev/prod stacks
- `env/` example env files
- `src/Controller/HealthController.php` health endpoint

## Notes
- Symfony 7 skeleton + ORM pack
- composer.lock is tracked for deterministic installs
- No secrets committed; use env files per environment

## CLI & Environment Variables
- The project includes a committed `.env` with safe dev defaults so `php bin/console` works locally.
- For overrides, create `.env.local` (gitignored).
- In Docker, environment variables come from docker-compose. To run CLI inside container:

  ```bash
  make bash
  php bin/console about
  ```


## Deploy locally (one command)

Basic usage:
```bash
./deploy.sh                # dev, pulls main, copies envs, rebuilds, installs, migrates, health-check
```

Options:
```bash
./deploy.sh dev --fresh            # drop volumes & rebuild
./deploy.sh staging --branch release/next
./deploy.sh prod --no-migrate
```

What it does:
1. Pulls latest from the selected branch
2. Ensures env files exist:
   - env/.env.<env> (created from env/.env.<env>.example if missing)
   - root .env for host CLI (dev-safe defaults)
3. Restarts Docker stack for the environment
4. Installs Composer deps inside php container
5. Runs doctrine migrations (can be skipped with --no-migrate)
6. Calls /health to verify


### Database & Migrations

- The project uses Doctrine Migrations. The `deploy.sh` script:
  - Ensures the DB exists: `doctrine:database:create --if-not-exists`
  - Runs migrations **only if** the migrations command is available.

- If you add entities and want an initial migration:
  ```bash
  make bash
  php bin/console make:migration
  php bin/console doctrine:migrations:migrate
  ```
- If the DB credentials change, update:
  - root .env (for host CLI)
  - env/.env.dev (used by docker-compose for containers)

### Migrations behavior

- `deploy.sh` will:
  - Create the DB if missing: `doctrine:database:create --if-not-exists`
  - Run `doctrine:migrations:migrate --allow-no-migration` so it **does not fail** when you have no migrations yet.
- When you add entities and want a first migration:
  ```bash
  make bash
  php bin/console make:migration
  php bin/console doctrine:migrations:migrate
  ```

## Database UI (Adminer)

- URL: http://localhost:8081
- Server: db        (inside Docker)
- Username: app
- Password: app
- Database: app

If you connect from a host DB client (Sequel Ace, TablePlus, DBeaver):
- Host: 127.0.0.1
- Port: 3307
- Username: app
- Password: app
- Database: app

> Prefer a native client? Try:
> - macOS: Sequel Ace (free), TablePlus (paid)
> - Cross‑platform: DBeaver (free), DataGrip (paid)

## Custom HTTPS dev domain

We use [mkcert](https://github.com/FiloSottile/mkcert) to generate a local CA and TLS certs for a wildcard domain.

### One-time setup (macOS)
```bash
brew install mkcert nss   # nss needed by Firefox
```

Use a custom domain base

deploy.sh can provision certs and /etc/hosts entries:

```bash
./deploy.sh dev --domain-base dev.local.test
# adds:
# - TLS certs under tls/dev.local.test/
# - 127.0.0.1 app.dev.local.test (and adminer/mail convenience hosts)
# App available at: https://app.dev.local.test
```

Change later: just re-run with a new --domain-base new.local.test.

Adminer and Mailpit stay on localhost:8081 / 8025 by default. You can optionally reverse-proxy them via Nginx in a future iteration.

## End‑to‑End tests (Playwright)

### Quick start (in Docker)
```bash
make up
make e2e-install
make e2e                # BASE_URL defaults to http://nginx inside the dev network
# or:
BASE_URL=https://app.<your-domain> make e2e
```

Local headed mode (UI)

```bash
npm install
npm run e2e:install
BASE_URL=http://localhost:8080 npm run e2e:ui
```

Run E2E after deploy

```bash
./deploy.sh dev --domain-base myshop.local.test --no-build --no-tls --no-hosts --e2e
```

Artifacts are written to e2e-report/ (HTML reporter).
