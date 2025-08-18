COMPOSE_DEV=docker compose -f compose/docker-compose.dev.yml
COMPOSE_PROD=docker compose -f compose/docker-compose.prod.yml

up:
	$(COMPOSE_DEV) up -d

down:
	$(COMPOSE_DEV) down

logs:
	$(COMPOSE_DEV) logs -f --tail=200

bash:
	$(COMPOSE_DEV) exec php bash

install:
	$(COMPOSE_DEV) exec php composer install --no-interaction --prefer-dist --optimize-autoloader

cc:
	$(COMPOSE_DEV) exec php php bin/console cache:clear

health:
	curl -sS http://localhost:8080/health || true

stan:
	$(COMPOSE_DEV) exec php vendor/bin/phpstan analyse -c phpstan.neon --no-progress

psalm:
	$(COMPOSE_DEV) exec php vendor/bin/psalm --no-cache

cs-fix:
	$(COMPOSE_DEV) exec php vendor/bin/php-cs-fixer fix --dry-run --diff
