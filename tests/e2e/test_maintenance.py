"""Maintenance / error behaviour when a backend is unreachable or unknown."""
from conftest import get


def test_unreachable_backend_returns_maintenance_502():
    # 'doesnotrun' has no listening web server, so the proxy must answer with
    # its 502 maintenance page instead of failing the connection.
    r = get("doesnotrun", "/")
    assert r.status_code == 502


def test_unknown_host_is_not_forwarded():
    # A Host that is not configured must never be proxied to a backend.
    r = get("unconfigured.example", "/")
    assert r.status_code in (404, 502, 444)
    assert "LOCALSERVER-OK" not in r.text
    assert "DEMO-OK" not in r.text
