#!/usr/bin/env bash
set -e

# Update
echo "> RUN git pull"

git pull

# Version Check: OpenSSL
echo "> GET OpenSSL x.y.z"

OPENSSL_VERSION=$(curl -fsSL "https://api.github.com/repos/openssl/openssl/releases?per_page=100" \
    | grep -o '"tag_name": *"openssl-[^"]*"' \
    | sed 's/.*openssl-\([^"]*\)".*/\1/' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -V \
    | tail -1)

echo "Found: OpenSSL ${OPENSSL_VERSION}"

# Version Check: Nginx
echo "> GET Nginx x.y.z"

NGINX_VERSION=$(curl -fsSL "https://nginx.org/en/download.html" \
    | grep -oE 'nginx-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz' \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
    | sort -V \
    | tail -1)

echo "Found: Nginx ${NGINX_VERSION}"

# Version Check: zstd-nginx-module
echo "> GET zstd-nginx-module commit"

ZSTD_NGINX_MODULE_COMMIT=$(curl -fsSL "https://api.github.com/repos/tokers/zstd-nginx-module/commits?per_page=1" \
    | grep -o '"sha": *"[^"]*"' \
    | head -1 \
    | sed 's/"sha": *"\([^"]*\)"/\1/')

echo "Found: zstd-nginx-module ${ZSTD_NGINX_MODULE_COMMIT}"

# Version Check: Debian Package List
echo "> GET Package List Checksum"

MAIN_RELEASE=$(curl -fsSL "http://deb.debian.org/debian/dists/bookworm/Release")
MAIN_PKG_HASH=$(echo "${MAIN_RELEASE}" | awk '/^SHA256:/{in_sha=1; next} in_sha && / main\/binary-amd64\/Packages$/{print $1; exit}')

SEC_RELEASE=$(curl -fsSL "https://security.debian.org/debian-security/dists/bookworm-security/Release")
SEC_PKG_HASH=$(echo "${SEC_RELEASE}" | awk '/^SHA256:/{in_sha=1; next} in_sha && / main\/binary-amd64\/Packages$/{print $1; exit}')

DEBIAN_PACKAGES_HASH="${MAIN_PKG_HASH:0:16}-${SEC_PKG_HASH:0:16}"

echo "Hash: Debian ${DEBIAN_PACKAGES_HASH}"

# Build
echo "> RUN docker compose build"

docker compose build \
    --build-arg OPENSSL_VERSION="${OPENSSL_VERSION}" \
    --build-arg NGINX_VERSION="${NGINX_VERSION}" \
    --build-arg ZSTD_NGINX_MODULE_COMMIT="${ZSTD_NGINX_MODULE_COMMIT}" \
    --build-arg DEBIAN_PACKAGES_HASH="${DEBIAN_PACKAGES_HASH}"

# Start
echo "> RUN docker compose up -d"

docker compose up -d
