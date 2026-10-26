FROM node:22-bookworm-slim AS nodejs

FROM php:8.4-fpm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        curl \
        ca-certificates \
        unzip \
        zip \
        rsync \
        libcurl4-openssl-dev \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libpng-dev \
        libwebp-dev \
        libonig-dev \
        libxml2-dev \
        libzip-dev \
        libicu-dev \
        libssl-dev \
    && docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg \
        --with-webp \
    && docker-php-ext-install -j"$(nproc)" \
        curl \
        pdo_mysql \
        mbstring \
        exif \
        pcntl \
        bcmath \
        gd \
        intl \
        zip \
        opcache \
        sockets \
    && pecl install redis \
    && docker-php-ext-enable redis \
    && rm -rf /var/lib/apt/lists/*

COPY --from=nodejs /usr/local/bin /usr/local/bin
COPY --from=nodejs /usr/local/lib/node_modules /usr/local/lib/node_modules

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

COPY docker/php/www.conf /usr/local/etc/php-fpm.d/www.conf

RUN groupadd -g 1000 www \
    && useradd -u 1000 -g www -m -s /bin/bash www \
    && mkdir -p /var/www \
    && chown www:www /var/www

WORKDIR /var/www

EXPOSE 9000

CMD ["php-fpm", "-F"]
