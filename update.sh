#!/usr/bin/env bash
set -e

echo "> RUN git pull"

git pull

echo "> GET OpenSSL 3.y.z | SET \$OPENSSL_VERSION"

OPENSSL_VERSION=$(curl -fsSL "https://api.github.com/repos/openssl/openssl/releases?per_page=100" \
    | grep -o '"tag_name": *"openssl-[^"]*"' \
    | sed 's/.*openssl-\([^"]*\)".*/\1/' \
    | grep -E '^3\.[0-9]+\.[0-9]+$' \
    | sort -V \
    | tail -1)

echo "Found: OpenSSL ${OPENSSL_VERSION}"

echo "> RUN docker compose build --build-arg OPENSSL_VERSION=\"\${OPENSSL_VERSION}\""

docker compose build --build-arg OPENSSL_VERSION="${OPENSSL_VERSION}"

echo "> RUN docker compose up -d"

docker compose up -d
