"""Shared fixtures for the HTTPS e2e suite."""
import os
import socket
import ssl
import time

import pytest
import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

DOMAIN    = os.environ.get("DOMAIN", "secure.example.com")
HTTP_URL  = os.environ.get("HTTP_URL", "http://secure.example.com:8080")
HTTPS_URL = os.environ.get("HTTPS_URL", "https://secure.example.com:8443")


def http_get(path: str = "/", allow_redirects: bool = False, **kwargs):
    return requests.get(HTTP_URL + path, allow_redirects=allow_redirects,
                        timeout=10, **kwargs)


def https_get(path: str = "/", **kwargs):
    # Pebble's chain is not trusted by the system; we verify the certificate
    # explicitly in the tests, so the request itself skips verification.
    return requests.get(HTTPS_URL + path, verify=False, timeout=10, **kwargs)


def peer_certificate_der(host: str = DOMAIN, port: int = 8443) -> bytes:
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    with socket.create_connection((host, port), timeout=10) as sock:
        with ctx.wrap_socket(sock, server_hostname=DOMAIN) as ssock:
            return ssock.getpeercert(binary_form=True)


def wait_until(predicate, timeout: int = 150, interval: float = 1.0):
    deadline = time.time() + timeout
    result = None
    while time.time() < deadline:
        try:
            result = predicate()
        except Exception:
            result = None
        if result:
            return result
        time.sleep(interval)
    return result


@pytest.fixture(scope="session", autouse=True)
def wait_for_http():
    # The proxy answers over HTTP from the start (before the certificate exists).
    def up():
        try:
            http_get("/")
            return True
        except requests.RequestException:
            return False
    if not wait_until(up, timeout=60):
        raise TimeoutError("reverse-proxy did not answer on HTTP within 60s")
