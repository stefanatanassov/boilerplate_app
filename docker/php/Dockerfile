FROM php:8.3-fpm

RUN apt-get update && apt-get install -y \
    git unzip libpq-dev libzip-dev libicu-dev libonig-dev libxml2-dev \
    && docker-php-ext-install intl pdo pdo_mysql zip mbstring xml \
    && rm -rf /var/lib/apt/lists/*

# Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/app
