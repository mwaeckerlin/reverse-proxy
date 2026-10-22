"""Basic-auth from the environment, without a mounted htpasswd file.

revproxy-auth-env protects envsecret and envsecret/admin with BASIC_AUTH,
filesecret with the file named by BASIC_AUTH_FILE, and mixedauth with both a
BASIC_AUTH entry (envuser) and a mounted htpasswd (authuser). Every user has the
password secretpass. The first BASIC_AUTH entry names ../escape and must be
ignored while the entries after it stay in effect.
"""
from conftest import AUTH_ENV_URL, get


def test_env_entry_requires_credentials():
    r = get("envsecret", "/", base=AUTH_ENV_URL)
    assert r.status_code == 401
    assert r.headers["WWW-Authenticate"] == 'Basic realm="envsecret"'


def test_env_entry_refuses_wrong_password():
    r = get("envsecret", "/", base=AUTH_ENV_URL, auth=("envuser", "wrong"))
    assert r.status_code == 401


def test_env_entry_passes_correct_credentials():
    r = get("envsecret", "/", base=AUTH_ENV_URL, auth=("envuser", "secretpass"))
    assert r.status_code == 200
    assert "LOCALSERVER-OK" in r.text


def test_env_entry_for_base_path_wins_over_host_entry():
    assert get("envsecret", "/admin/", base=AUTH_ENV_URL).status_code == 401
    assert get("envsecret", "/admin/", base=AUTH_ENV_URL,
               auth=("envuser", "secretpass")).status_code == 401
    assert get("envsecret", "/admin/", base=AUTH_ENV_URL,
               auth=("adminuser", "secretpass")).status_code != 401


def test_secret_file_entry_protects_host():
    assert get("filesecret", "/", base=AUTH_ENV_URL).status_code == 401
    r = get("filesecret", "/", base=AUTH_ENV_URL, auth=("fileuser", "secretpass"))
    assert r.status_code == 200
    assert "LOCALSERVER-OK" in r.text


def test_mounted_file_wins_over_env_entry():
    ok = get("mixedauth", "/", base=AUTH_ENV_URL, auth=("authuser", "secretpass"))
    assert ok.status_code == 200
    refused = get("mixedauth", "/", base=AUTH_ENV_URL, auth=("envuser", "secretpass"))
    assert refused.status_code == 401
