#!/usr/bin/env bash
set -e

echo "> RUN git pull"

git pull

echo "> GET OpenSSL x.y.z"

OPENSSL_VERSION=$(curl -fsSL "https://api.github.com/repos/openssl/openssl/releases?per_page=100" \
    | grep -o '"tag_name": *"openssl-[^"]*"' \
    | sed 's/.*openssl-\([^"]*\)".*/\1/' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -V \
    | tail -1)

echo "Found: OpenSSL ${OPENSSL_VERSION}"

echo "> GET Nginx x.y.z"

NGINX_VERSION=$(curl -fsSL "https://nginx.org/en/download.html" \
    | grep -oE 'nginx-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz' \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
    | sort -V \
    | tail -1)

echo "Found: Nginx ${NGINX_VERSION}"

echo "> RUN docker compose build --build-arg OPENSSL_VERSION=\"${OPENSSL_VERSION}\" --build-arg NGINX_VERSION=\"${NGINX_VERSION}\""

docker compose build --build-arg OPENSSL_VERSION="${OPENSSL_VERSION}" --build-arg NGINX_VERSION="${NGINX_VERSION}"

echo "> RUN docker compose up -d"

docker compose up -d
