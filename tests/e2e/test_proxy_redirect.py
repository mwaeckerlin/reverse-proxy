"""Redirects of the backend.

The backend `redirector` answers every request with a redirect to its own
internal address. By default the proxy rewrites that address to the public
host; for the hosts in PROXY_REDIRECT_OFF it passes the header unchanged.
"""
from conftest import get


def test_backend_redirect_is_rewritten_to_the_public_host():
    r = get("redirect-on", "/", allow_redirects=False)
    assert r.status_code == 302
    assert r.headers["Location"] == "http://redirect-on:8080/landed/"


def test_proxy_redirect_off_passes_the_backend_address():
    r = get("redirect-off", "/", allow_redirects=False)
    assert r.status_code == 302
    assert r.headers["Location"] == "http://redirector:8080/landed/"
