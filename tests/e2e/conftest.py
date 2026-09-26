"""Shared fixtures for the reverse-proxy e2e suite.

Each proxy instance routes by Host header (nginx server_name), so every request
goes to a proxy endpoint with an explicit Host that selects the backend. The
different proxy URLs correspond to the different configuration sources under
test (environment, file, mixed, basic-auth, live reload).
"""
import os
import time

import pytest
import requests


# ----------------------------------------------------------------- Config ---

REVPROXY_URL = os.environ.get("REVPROXY_URL", "http://reverse-proxy:8080")
FILE_URL     = os.environ.get("FILE_URL",     "http://revproxy-file:8080")
MIXED_URL    = os.environ.get("MIXED_URL",    "http://revproxy-mixed:8080")
AUTH_URL     = os.environ.get("AUTH_URL",     "http://revproxy-auth:8080")
REALM_URL    = os.environ.get("REALM_URL",    "http://revproxy-auth-realm:8080")
BADREALM_URL = os.environ.get("BADREALM_URL", "http://revproxy-auth-badrealm:8080")
RELOAD_URL   = os.environ.get("RELOAD_URL",   "http://revproxy-reload:8080")

ALL_PROXIES = [REVPROXY_URL, FILE_URL, MIXED_URL, AUTH_URL, REALM_URL, BADREALM_URL, RELOAD_URL]


# ----------------------------------------------------------- Helpers -------

def get(host: str, path: str = "/", base: str = REVPROXY_URL,
        allow_redirects: bool = True, **kwargs):
    """GET path from a proxy, selecting the virtual host via the Host header."""
    headers = kwargs.pop("headers", {})
    headers["Host"] = host
    return requests.get(
        base + path,
        headers=headers,
        allow_redirects=allow_redirects,
        timeout=10,
        **kwargs,
    )


def wait_for_proxy(base: str, host: str = "any", timeout: int = 60) -> None:
    """Wait until a proxy answers at all (any HTTP status counts as up)."""
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            get(host, "/", base=base, allow_redirects=False)
            return
        except requests.RequestException as exc:  # connection refused / reset
            last = exc
            time.sleep(1)
    raise TimeoutError(f"{base} did not become ready within {timeout}s: {last}")


def wait_until(predicate, timeout: int = 30, interval: float = 0.5):
    """Poll predicate() until it returns a truthy value or the timeout elapses."""
    deadline = time.time() + timeout
    result = None
    while time.time() < deadline:
        result = predicate()
        if result:
            return result
        time.sleep(interval)
    return result


# --------------------------------------------------------- Fixtures --------

@pytest.fixture(scope="session", autouse=True)
def wait_for_services():
    for base in ALL_PROXIES:
        wait_for_proxy(base)
