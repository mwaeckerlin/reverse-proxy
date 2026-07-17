#!/usr/bin/env bash
# Run the HTTPS e2e suite: the reverse-proxy terminates TLS with a real
# certificate that mwaeckerlin/letsencrypt obtains from a local Pebble ACME test
# server. Verifies HTTPS serving, the HTTP->HTTPS switch on certificate arrival
# (certificate watch), and the presented certificate.
# Usage: bash tests/run-https-e2e.sh [pytest-args...]
set -euo pipefail

COMPOSE="tests/e2e-https/docker-compose.yml"
cd "$(dirname "$0")/.."

cleanup() {
    docker compose -f "$COMPOSE" down -v --remove-orphans 2>/dev/null || true
}
trap cleanup EXIT

# Always start from a clean, defined state.
echo "==> Clean start (removing stale volumes/containers)..."
cleanup

echo "==> Building test stack..."
docker compose -f "$COMPOSE" build --quiet

echo "==> Starting Pebble, letsencrypt, proxy and backend..."
docker compose -f "$COMPOSE" up -d --remove-orphans

echo "==> Running tests..."
EXIT=0
docker compose -f "$COMPOSE" run --build --rm test-runner "$@" || EXIT=$?

if [[ $EXIT -ne 0 ]]; then
    echo "==> Collecting logs on failure..."
    docker compose -f "$COMPOSE" logs 2>&1 | tail -200
fi

exit $EXIT
