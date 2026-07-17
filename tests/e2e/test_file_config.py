"""Configuration via a mounted /config/reverse-proxy.conf file (no environment).

The file uses the simplified format without the -- prefix:
    forward   filehost   localserver:8080
    redirect  fileredir  example.com
"""
from conftest import FILE_URL, get


def test_file_forward_is_served():
    r = get("filehost", "/", base=FILE_URL)
    assert r.status_code == 200
    assert "LOCALSERVER-OK" in r.text


def test_file_redirect_is_permanent():
    r = get("fileredir", "/", base=FILE_URL, allow_redirects=False)
    assert r.status_code == 301
    assert "example.com" in r.headers.get("Location", "")


def test_file_unknown_host_not_forwarded():
    r = get("unconfigured.example", "/", base=FILE_URL)
    assert r.status_code == 404
