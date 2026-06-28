#!/usr/bin/env bash
set -e

# Update
echo "> UPDATE"

sudo git pull

# Reload
echo "> RELOAD"

docker compose exec nginx nginx -s reload
