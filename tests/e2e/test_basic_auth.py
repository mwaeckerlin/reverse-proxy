"""Basic-auth protected forward.

revproxy-auth forwards "secret" to localserver and mounts a htpasswd at
/etc/nginx/basic-auth/secret.htpasswd (user authuser / password secretpass).
"""
from conftest import AUTH_URL, get


def test_no_credentials_is_unauthorized():
    r = get("secret", "/", base=AUTH_URL)
    assert r.status_code == 401
    assert "WWW-Authenticate" in r.headers


def test_wrong_credentials_is_unauthorized():
    r = get("secret", "/", base=AUTH_URL, auth=("authuser", "wrong"))
    assert r.status_code == 401


def test_correct_credentials_pass_through():
    r = get("secret", "/", base=AUTH_URL, auth=("authuser", "secretpass"))
    assert r.status_code == 200
    assert "LOCALSERVER-OK" in r.text
