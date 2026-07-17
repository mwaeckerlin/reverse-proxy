"""Security headers on proxied responses.

The proxy is authoritative for Referrer-Policy and X-Content-Type-Options:
it must add them when the backend sends none (backend ``plain``) and it must
replace a backend copy instead of duplicating it (backend ``localserver``,
mwaeckerlin/nginx, which sends its own) — exactly one header either way.
"""
from conftest import get


def test_headers_added_for_headerless_backend():
    r = get("plain", "/")
    assert r.status_code == 200
    assert r.headers.get("X-Content-Type-Options") == "nosniff"
    assert r.headers.get("Referrer-Policy") == "no-referrer"


def test_headers_not_duplicated_for_backend_with_own_headers():
    r = get("localhost", "/")
    assert r.status_code == 200
    assert r.headers.get("X-Content-Type-Options") == "nosniff"
    assert r.headers.get("Referrer-Policy") == "no-referrer"
