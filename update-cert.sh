#!/usr/bin/env bash
set -e

CERT_NAME="${1:-nercone.dev}"
CERT_DIR="/etc/letsencrypt/live/${CERT_NAME}"

# Renew Certificates
echo "> RENEW"

certbot renew

# Upload to Cloudflare
echo "> UPLOAD"

if [ -z "${CF_TOKEN}" ]; then
    echo "WARNING: CF_TOKEN is not set — Skipping Cloudflare upload"
else
    if ! command -v jq &>/dev/null; then
        echo "ERROR: jq is required for Cloudflare upload but not found in PATH"
        exit 1
    fi

    if [ ! -f "${CERT_DIR}/fullchain.pem" ] || [ ! -f "${CERT_DIR}/privkey.pem" ]; then
        echo "ERROR: Certificate files not found in ${CERT_DIR}"
        exit 1
    fi

    CERT=$(cat "${CERT_DIR}/fullchain.pem")
    KEY=$(cat "${CERT_DIR}/privkey.pem")

    CF_API="https://api.cloudflare.com/client/v4"
    CF_HEADERS=(-H "Authorization: Bearer ${CF_TOKEN}" -H "Content-Type: application/json")

    for DOMAIN in \
        "nercone.dev" \
        "diamondgotcat.net" \
        "d-g-c.net" \
        "nerc1.dev"
    do
        echo "  [${DOMAIN}] Fetching Zone ID..."

        ZONE_RESPONSE=$(curl -fsSL "${CF_HEADERS[@]}" "${CF_API}/zones?name=${DOMAIN}")
        ZONE_ID=$(echo "${ZONE_RESPONSE}" | jq -r '.result[0].id // empty')

        if [ -z "${ZONE_ID}" ]; then
            echo "  [${DOMAIN}] ERROR: Zone Not Found — Skipping"
            continue
        fi

        echo "  [${DOMAIN}] Zone ID: ${ZONE_ID}"

        EXISTING=$(curl -fsSL "${CF_HEADERS[@]}" "${CF_API}/zones/${ZONE_ID}/custom_certificates")
        CERT_ID=$(echo "${EXISTING}" | jq -r --arg domain "${DOMAIN}" '
            [ .result[] | select(
                .hosts[] | ltrimstr("*.") | . == $domain or ($domain | endswith("." + .))
            )] | .[0].id // empty
        ')

        CERT_BODY=$(jq -cn \
            --arg cert "${CERT}" \
            --arg key "${KEY}" \
            '{certificate: $cert, private_key: $key, bundle_method: "ubiquitous"}')

        if [ -z "${CERT_ID}" ]; then
            RESULT=$(curl -fsSL -X POST "${CF_HEADERS[@]}" \
                -d "${CERT_BODY}" \
                "${CF_API}/zones/${ZONE_ID}/custom_certificates")
            ACTION="Uploaded"
        else
            RESULT=$(curl -fsSL -X PATCH "${CF_HEADERS[@]}" \
                -d "${CERT_BODY}" \
                "${CF_API}/zones/${ZONE_ID}/custom_certificates/${CERT_ID}")
            ACTION="Updated"
        fi

        if echo "${RESULT}" | jq -e '.success == true' &>/dev/null; then
            EXPIRES=$(echo "${RESULT}" | jq -r '.result.expires_on // "unknown"')
            echo "  [${DOMAIN}] ${ACTION} certificate successfully (expires: ${EXPIRES})"
        else
            echo "  [${DOMAIN}] ERROR: $(echo "${RESULT}" | jq -r '.errors[]?.message // "unknown error"')"
        fi
    done
fi

# Restart
echo "> RESTART"

docker compose restart
