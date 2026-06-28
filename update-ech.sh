#!/usr/bin/env bash
set -e

PUBLIC_NAME="${1:-ech.nerc1.dev}"
ECH_DIR="$(cd "$(dirname "$0")" && pwd)/nginx/ech"
PEM_FILE="${ECH_DIR}/${PUBLIC_NAME}.pem"

# Version Check: OpenSSL
echo "> VERSION OpenSSL"

OPENSSL_VERSION=$(curl -fsSL "https://api.github.com/repos/openssl/openssl/releases?per_page=100" \
    | grep -o '"tag_name": *"openssl-[^"]*"' \
    | sed 's/.*openssl-\([^"]*\)".*/\1/' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -V \
    | tail -1)

echo "OpenSSL ${OPENSSL_VERSION}"

# Prepare Build Container
echo "> PREPARE"

docker build --target openssl-builder -t proxy-openssl-builder --build-arg OPENSSL_VERSION="${OPENSSL_VERSION}" .

# Generate ECH Key
echo "> GENERATE ${PUBLIC_NAME}"

docker run --rm -v "${ECH_DIR}:/ech" proxy-openssl-builder /usr/local/bin/openssl ech -public_name "${PUBLIC_NAME}" -out "/ech/${PUBLIC_NAME}.pem"

echo "ECH key generated: ${PEM_FILE}"

# Update DNS Records
echo "> CAVEATS"

ECHCONFIG=$(sudo awk '/-----BEGIN ECHCONFIG-----/{found=1; next} /-----END ECHCONFIG-----/{found=0} found' "${PEM_FILE}" | tr -d '\n')

echo "The HTTPS records for each domain are scheduled to be updated as follows:"

for DOMAIN in \
    "nercone.dev." \
    "diamondgotcat.net." \
    "d-g-c.net." \
    "nerc1.dev."
do
    printf "%-28s HTTPS 1 . ech=%s\n" "${DOMAIN}" "${ECHCONFIG}"
done

echo "> UPDATE"

if [ -z "${CF_TOKEN}" ]; then
    echo "WARNING: CF_TOKEN is not set — Skipping DNS update"
else
    if ! command -v jq &>/dev/null; then
        echo "ERROR: jq is required for DNS update but not found in PATH"
        exit 1
    fi

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

        RECORD_RESPONSE=$(curl -fsSL "${CF_HEADERS[@]}" \
            "${CF_API}/zones/${ZONE_ID}/dns_records?type=HTTPS&name=${DOMAIN}")
        RECORD_ID=$(echo "${RECORD_RESPONSE}" | jq -r '.result[0].id // empty')

        EXISTING_VALUE=$(echo "${RECORD_RESPONSE}" | jq -r '.result[0].data.value // empty')
        EXISTING_TTL=$(echo "${RECORD_RESPONSE}" | jq -r '.result[0].ttl // 1')

        BASE_VALUE=$(echo "${EXISTING_VALUE}" | sed -E 's/(^| )ech=[^ ]*//g' | sed 's/^ *//;s/ *$//')
        if [ -n "${BASE_VALUE}" ]; then
            MERGED_VALUE="${BASE_VALUE} ech=${ECHCONFIG}"
        else
            MERGED_VALUE="ech=${ECHCONFIG}"
        fi

        RECORD_BODY=$(jq -cn \
            --arg domain "${DOMAIN}" \
            --arg val "${MERGED_VALUE}" \
            --argjson ttl "${EXISTING_TTL}" \
            '{type:"HTTPS", name:$domain, ttl:$ttl, data:{priority:1, target:".", value:$val}}')

        if [ -z "${RECORD_ID}" ]; then
            RESULT=$(curl -fsSL -X POST "${CF_HEADERS[@]}" \
                -d "${RECORD_BODY}" \
                "${CF_API}/zones/${ZONE_ID}/dns_records")
            ACTION="Created"
        else
            RESULT=$(curl -fsSL -X PUT "${CF_HEADERS[@]}" \
                -d "${RECORD_BODY}" \
                "${CF_API}/zones/${ZONE_ID}/dns_records/${RECORD_ID}")
            ACTION="Updated"
        fi

        if echo "${RESULT}" | jq -e '.success == true' &>/dev/null; then
            echo "  [${DOMAIN}] ${ACTION} HTTPS record successfully"
        else
            echo "  [${DOMAIN}] ERROR: $(echo "${RESULT}" | jq -r '.errors[]?.message // "unknown error"')"
        fi
    done
fi

# Restart
echo "> RESTART"

docker compose restart
