"""Forwarding: each configured Host is proxied to its backend web server."""
from conftest import get


def test_localhost_forwarded_to_localserver():
    r = get("localhost", "/")
    assert r.status_code == 200
    assert "LOCALSERVER-OK" in r.text


def test_demo_forwarded_to_demo_backend():
    r = get("demo", "/")
    assert r.status_code == 200
    assert "DEMO-OK" in r.text


def test_test_forwarded_to_test_backend():
    r = get("test", "/")
    assert r.status_code == 200
    assert "TEST-OK" in r.text


def test_forward_isolates_backends():
    # The demo host must not leak the localserver backend and vice versa.
    assert "DEMO-OK" not in get("localhost", "/").text
    assert "LOCALSERVER-OK" not in get("demo", "/").text


def test_path_based_forward():
    # A forward with a base path (pathhost/app) proxies that path...
    r = get("pathhost", "/app/")
    assert r.status_code == 200
    assert "LOCALSERVER-OK" in r.text


def test_path_forward_leaves_root_unconfigured():
    # ...and only that path: the root has no location and returns not-found.
    r = get("pathhost", "/")
    assert r.status_code == 404
