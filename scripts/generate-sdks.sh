#!/usr/bin/env bash
# generate-sdks.sh — Generate client SDKs from the IronLedger OpenAPI specification.
#
# Usage:
#   ./scripts/generate-sdks.sh [server_url]
#
# Default server URL: http://localhost:8080
#
# Prerequisites:
#   - Node.js and npm installed
#   - A running IronLedger server (rebar3 shell)
#
# The script uses npx @openapitools/openapi-generator-cli (auto-downloaded on first run).

set -euo pipefail

SERVER_URL="${1:-http://localhost:8080}"
SPEC_URL="${SERVER_URL}/api/v1/openapi.json"
SPEC_FILE="sdk/openapi.json"
SDK_DIR="sdk"

echo "==> IronLedger SDK Generator"
echo "    Server: ${SERVER_URL}"
echo "    Spec:   ${SPEC_URL}"
echo ""

# Fetch the OpenAPI spec from the running server.
echo "==> Fetching OpenAPI spec..."
curl --silent --fail --show-error \
    --output "${SPEC_FILE}" \
    "${SPEC_URL}"
echo "    Saved to ${SPEC_FILE}"
echo ""

# Helper: run openapi-generator-cli for a given language.
generate_sdk() {
    local LANG="$1"
    local OUTPUT_DIR="${SDK_DIR}/${2}"
    local EXTRA_ARGS="${3:-}"

    echo "==> Generating ${LANG} SDK → ${OUTPUT_DIR}"
    # shellcheck disable=SC2086
    npx --yes @openapitools/openapi-generator-cli generate \
        --input-spec "${SPEC_FILE}" \
        --generator-name "${LANG}" \
        --output "${OUTPUT_DIR}" \
        --package-name ironledger \
        ${EXTRA_ARGS}
    echo "    Done."
}

generate_sdk java    java    "--additional-properties=groupId=com.ironledger,artifactId=ironledger-client"
generate_sdk python  python  ""
generate_sdk typescript-node nodejs "--additional-properties=npmName=ironledger,supportsES6=true"
generate_sdk csharp  dotnet  "--additional-properties=packageName=IronLedger"

echo ""
echo "==> All SDKs generated successfully."
echo "    Java:    ${SDK_DIR}/java"
echo "    Python:  ${SDK_DIR}/python"
echo "    Node.js: ${SDK_DIR}/nodejs"
echo "    .NET:    ${SDK_DIR}/dotnet"
