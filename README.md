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

