"""Basic-auth protected forward.

revproxy-auth forwards "secret" to localserver and mounts a htpasswd at
/etc/nginx/basic-auth/secret.htpasswd (user authuser / password secretpass).
revproxy-auth-realm does the same with BASIC_AUTH_REALM set, and
revproxy-auth-badrealm with a realm that tries to close the quote and switch
the protection off.
"""
from conftest import AUTH_URL, BADREALM_URL, REALM_URL, get


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


def test_default_realm_is_the_host():
    r = get("secret", "/", base=AUTH_URL)
    assert r.headers["WWW-Authenticate"] == 'Basic realm="secret"'


def test_realm_from_environment():
    r = get("secret", "/", base=REALM_URL)
    assert r.status_code == 401
    assert r.headers["WWW-Authenticate"] == 'Basic realm="Team Area"'


def test_hostile_realm_keeps_the_protection():
    r = get("secret", "/", base=BADREALM_URL)
    assert r.status_code == 401
    assert r.headers["WWW-Authenticate"] == 'Basic realm="secret"'
    ok = get("secret", "/", base=BADREALM_URL, auth=("authuser", "secretpass"))
    assert ok.status_code == 200
