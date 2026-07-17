"""Redirects: a configured Host answers with a permanent redirect."""
from conftest import get


def test_extern_redirects_permanently():
    r = get("extern", "/", allow_redirects=False)
    assert r.status_code == 301
    assert "example.com" in r.headers.get("Location", "")


def test_www_prefix_redirects_to_bare_host():
    # The proxy adds a www.<host> -> <host> redirect for every server.
    r = get("www.localhost", "/", allow_redirects=False)
    assert r.status_code == 302
    assert "localhost" in r.headers.get("Location", "")


def test_redirect_with_base_path():
    # A redirect with a base path (redirbase/old) redirects only that path.
    r = get("redirbase", "/old", allow_redirects=False)
    assert r.status_code == 301
    assert "example.com" in r.headers.get("Location", "")


def test_redirect_base_leaves_other_paths():
    r = get("redirbase", "/other", allow_redirects=False)
    assert r.status_code != 301
