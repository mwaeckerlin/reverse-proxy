#!/usr/bin/env bash
# Config contract: the nginx settings an operator may change are environment
# variables with defaults. `nginx -T` in the running container prints the
# configuration run-nginx rendered, once with the defaults, once with every
# variable set and once with invalid values, which must fall back to the
# default with a warning instead of reaching the configuration.
#
# Usage: tests/config-contract.sh IMAGE

set -uo pipefail

IMAGE="${1:?usage: tests/config-contract.sh IMAGE}"

PASS=0
FAIL=0
declare -a FAILED_NAMES

_pass() { PASS=$((PASS + 1)); echo "  PASS  $1"; }
_fail() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); echo "  FAIL  $1: $2"; }

# _effective [-e VAR=value ...]: the rendered configuration and the container log
_effective() {
    local container output=""
    container=$(docker run -d --rm --pull=never -e DHPARAM=512 \
        -e "FORWARD=example.org backend:8080" "$@" "${IMAGE}")
    for attempt in $(seq 1 60); do
        if output=$(docker exec "${container}" /usr/sbin/nginx -T 2>&1) \
            && grep -q 'proxy_read_timeout' <<< "${output}"; then
            break
        fi
        sleep 1
    done
    output+=$'\n'$(docker logs "${container}" 2>&1)
    docker stop "${container}" > /dev/null 2>&1
    echo "${output}"
}

# _expect NAME OUTPUT "LINE..." : every expected text appears in the output
_expect() {
    local name="$1" output="$2" expected="$3" line
    while IFS= read -r line; do
        if ! grep -qF -- "${line}" <<< "${output}"; then
            _fail "${name}" "'${line}' not in the effective configuration"
            return
        fi
    done <<< "${expected}"
    _pass "${name}"
}

echo "==> Config contract: settings from the environment"

if ! docker image inspect "${IMAGE}" > /dev/null 2>&1; then
    _fail "${IMAGE}_image_exists" "image not built — run 'npm run build' first"
else
    DEFAULTS=$(_effective)
    _expect settings_default "${DEFAULTS}" 'worker_connections 1024;
keepalive_timeout 65;
client_max_body_size 0;
client_body_buffer_size 128k;
proxy_buffers 32 4k;
proxy_connect_timeout 1200;
proxy_read_timeout 86400;
proxy_send_timeout 1200;
send_timeout 1200;
https "max-age=31536000";'

    SET=$(_effective -e WORKER_CONNECTIONS=512 -e KEEPALIVE_TIMEOUT=30s \
        -e CLIENT_MAX_BODY_SIZE=5m -e CLIENT_BODY_BUFFER_SIZE=64k -e "PROXY_BUFFERS=16 8k" \
        -e PROXY_CONNECT_TIMEOUT=30s -e PROXY_READ_TIMEOUT=600 -e PROXY_SEND_TIMEOUT=60s \
        -e SEND_TIMEOUT=90 -e HSTS_MAX_AGE=600)
    _expect settings_from_environment "${SET}" 'worker_connections 512;
keepalive_timeout 30s;
client_max_body_size 5m;
client_body_buffer_size 64k;
proxy_buffers 16 8k;
proxy_connect_timeout 30s;
proxy_read_timeout 600;
proxy_send_timeout 60s;
send_timeout 90;
https "max-age=600";'

    INVALID=$(_effective -e "PROXY_READ_TIMEOUT=10; return 200 injected" -e HSTS_MAX_AGE=forever \
        -e "PROXY_BUFFERS=many" -e CLIENT_MAX_BODY_SIZE=1x)
    _expect invalid_settings_fall_back "${INVALID}" 'proxy_read_timeout 86400;
https "max-age=31536000";
proxy_buffers 32 4k;
client_max_body_size 0;
ignoring invalid PROXY_READ_TIMEOUT=10; return 200 injected, using 86400
ignoring invalid HSTS_MAX_AGE=forever, using 31536000
ignoring invalid PROXY_BUFFERS=many, using 32 4k
ignoring invalid CLIENT_MAX_BODY_SIZE=1x, using 0'
    if grep -q 'return 200 injected' <<< "$(grep -v 'ignoring invalid' <<< "${INVALID}")"; then
        _fail "invalid_settings_not_injected" "the invalid value reached the configuration"
    else
        _pass "invalid_settings_not_injected"
    fi
fi

echo ""
echo "==> Config contract results: ${PASS} passed, ${FAIL} failed"
if [[ ${FAIL} -gt 0 ]]; then
    echo "==> Failed contracts: ${FAILED_NAMES[*]}"
    exit 1
fi
