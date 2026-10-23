"""/.well-known: only the ACME challenge is answered by the proxy itself,
every other path reaches the backend (Nextcloud needs webfinger, nodeinfo,
caldav and carddav there)."""
from conftest import get


def test_well_known_reaches_the_backend():
    # redirector answers every request with its own redirect; the proxy's own
    # answer would be its 404 page
    r = get("redirect-off", "/.well-known/webfinger", allow_redirects=False)
    assert r.status_code == 302
    assert r.headers.get("Location") == "http://redirector:8080/landed/"


def test_acme_challenge_is_answered_by_the_proxy():
    r = get("redirect-off", "/.well-known/acme-challenge/nothing", allow_redirects=False)
    assert r.status_code == 404
    assert "Location" not in r.headers
