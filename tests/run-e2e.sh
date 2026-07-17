#!/usr/bin/env bash
# Run the full reverse-proxy e2e test suite: build the proxy image, bring up the
# backends and one proxy per configuration source (environment, file, mixed,
# basic-auth, live reload), and check forwarding, redirects, the maintenance
# page, basic-auth, the configuration sources and the startup contract.
# Usage: bash tests/run-e2e.sh [pytest-args...]
set -euo pipefail

COMPOSE="tests/e2e/docker-compose.yml"
cd "$(dirname "$0")/.."

cleanup() {
    docker compose -f "$COMPOSE" down -v --remove-orphans 2>/dev/null || true
}
trap cleanup EXIT

# Always start from a clean, defined state: remove any volumes/containers left
# over from a previous run (e.g. one that was killed before its cleanup ran).
echo "==> Clean start (removing stale volumes/containers)..."
cleanup

echo "==> Building test stack..."
docker compose -f "$COMPOSE" build --quiet

echo "==> Starting backends and proxies..."
# Everything except the profiled test-runner.
docker compose -f "$COMPOSE" up -d --remove-orphans

echo "==> Running tests..."
# --build so the profiled test-runner (skipped by `compose build`) always ships
# the current test files.
EXIT=0
docker compose -f "$COMPOSE" run --build --rm test-runner "$@" || EXIT=$?

if [[ $EXIT -ne 0 ]]; then
    echo "==> Collecting logs on failure..."
    docker compose -f "$COMPOSE" logs 2>&1 | tail -160
fi

exit $EXIT
