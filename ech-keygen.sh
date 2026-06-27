#!/usr/bin/env bash
set -e

PUBLIC_NAME="${1:-nercone.dev}"
ECH_DIR="$(cd "$(dirname "$0")" && pwd)/ech"
PEM_FILE="${ECH_DIR}/${PUBLIC_NAME}.pem"

mkdir -p "${ECH_DIR}"

# Prepare Build Container
echo "> PREPARE"

docker build --target builder -t proxy-builder .

# Generate ECH Key
echo "> GENERATE ${PUBLIC_NAME}"

docker run --rm \
    -v "${ECH_DIR}:/ech" \
    proxy-builder \
    /usr/local/bin/openssl ech \
        -public_name "${PUBLIC_NAME}" \
        -pemout "/ech/${PUBLIC_NAME}.pem"

echo ""
echo "ECH key generated: ${PEM_FILE}"
echo ""
echo "Add the following 'ech=' value to your DNS HTTPS records:"
echo ""

ECHCONFIG=$(awk '/-----BEGIN ECHCONFIG-----/{found=1; next} /-----END ECHCONFIG-----/{found=0} found' "${PEM_FILE}" | tr -d '\n')

for DOMAIN in \
    "nercone.dev." \
    "*.nercone.dev." \
    "diamondgotcat.net." \
    "*.diamondgotcat.net." \
    "d-g-c.net." \
    "*.d-g-c.net." \
    "nerc1.dev." \
    "*.nerc1.dev."
do
    printf "%-28s HTTPS 1 . ech=%s\n" "${DOMAIN}" "${ECHCONFIG}"
done
