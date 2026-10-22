"""Request size and read timeout from the environment.

reverse-proxy runs with the defaults (no size limit, a read timeout of one
day); revproxy-limits sets CLIENT_MAX_BODY_SIZE=1k and PROXY_READ_TIMEOUT=1s,
and a PROXY_SEND_TIMEOUT that tries to inject `return 200 injected`. The
backend slow answers after three seconds.
"""
import requests

from conftest import LIMITS_URL, REVPROXY_URL, get

BODY = b"x" * 2048


def post(host: str, base: str):
    return requests.post(base + "/", data=BODY, headers={"Host": host}, timeout=10)


def test_body_without_limit_is_forwarded():
    assert post("localhost", REVPROXY_URL).status_code != 413


def test_body_over_limit_is_refused():
    assert post("localhost", LIMITS_URL).status_code == 413


def test_slow_backend_within_default_read_timeout():
    r = get("slow", "/")
    assert r.status_code == 200
    assert r.text == "SLOW-OK"


def test_slow_backend_over_read_timeout():
    r = get("slow", "/", base=LIMITS_URL)
    assert r.status_code == 504
    assert r.elapsed.total_seconds() < 3


def test_invalid_value_cannot_inject_a_directive():
    r = get("localhost", "/", base=LIMITS_URL)
    assert r.status_code == 200
    assert "LOCALSERVER-OK" in r.text
    assert "injected" not in r.text
