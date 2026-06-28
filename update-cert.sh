#!/usr/bin/env bash
set -e

# Renew Certificates
echo "> RENEW"

sudo certbot renew

# Restart
echo "> RESTART"

docker compose restart
