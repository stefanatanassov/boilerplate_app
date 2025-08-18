# Boilerplate App (Symfony 7 + Docker)

## Quickstart (Dev)
0. Pull latest code
1. Copy env: `cp env/.env.dev.example env/.env.dev`
2. Start stack: `make up`
3. Install deps: `make install`
4. Check health: http://localhost:8080/health

Services:
- App: http://localhost:8080
- Mailpit: http://localhost:8025
- MySQL: port 3307 (local)

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
- No secrets committed; use env files per environment
