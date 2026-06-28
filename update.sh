#!/usr/bin/env bash
set -e

# Update
echo "> UPDATE"

git pull

# Version Check: Nginx
echo "> VERSION Nginx"

NGINX_VERSION=$(curl -fsSL "https://nginx.org/en/download.html" \
    | grep -oE 'nginx-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz' \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
    | sort -V \
    | tail -1)

echo "Nginx ${NGINX_VERSION}"

# Version Check: OpenSSL
echo "> VERSION OpenSSL"

OPENSSL_VERSION=$(curl -fsSL "https://api.github.com/repos/openssl/openssl/releases?per_page=100" \
    | grep -o '"tag_name": *"openssl-[^"]*"' \
    | sed 's/.*openssl-\([^"]*\)".*/\1/' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -V \
    | tail -1)

echo "OpenSSL ${OPENSSL_VERSION}"

# Version Check: Packages
echo "> VERSION Packages"

MAIN_RELEASE=$(curl -fsSL "http://deb.debian.org/debian/dists/bookworm/Release")
MAIN_HASH=$(echo "${MAIN_RELEASE}" | awk '/^SHA256:/{in_sha=1; next} in_sha && / main\/binary-amd64\/Packages$/{print $1; exit}')

SECURITY_RELEASE=$(curl -fsSL "https://security.debian.org/debian-security/dists/bookworm-security/Release")
SECURITY_HASH=$(echo "${SEC_RELEASE}" | awk '/^SHA256:/{in_sha=1; next} in_sha && / main\/binary-amd64\/Packages$/{print $1; exit}')

PACKAGES_VERSION="${MAIN_HASH:0:16}-${SECURITY_HASH:0:16}"

echo "Packages ${PACKAGES_VERSION}"

# Build
echo "> BUILD"

docker compose build \
    --build-arg NGINX_VERSION="${NGINX_VERSION}" \
    --build-arg OPENSSL_VERSION="${OPENSSL_VERSION}" \
    --build-arg PACKAGES_VERSION="${PACKAGES_VERSION}"

# Start
echo "> START"

docker compose up -d
