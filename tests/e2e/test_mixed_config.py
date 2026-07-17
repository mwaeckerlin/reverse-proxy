"""Mixed configuration: environment FORWARD/REDIRECT merged with the file.

Environment (revproxy-mixed):    mixedenv -> localserver, conflict -> localserver
File (config-mixed):             mixedfile -> demo,        conflict -> demo

Both sources apply (merge); on the shared source "conflict" the file wins.
"""
from conftest import MIXED_URL, get


def test_env_only_rule_applies():
    r = get("mixedenv", "/", base=MIXED_URL)
    assert r.status_code == 200
    assert "LOCALSERVER-OK" in r.text


def test_file_only_rule_applies():
    r = get("mixedfile", "/", base=MIXED_URL)
    assert r.status_code == 200
    assert "DEMO-OK" in r.text


def test_file_wins_on_conflict():
    # "conflict" is localserver in the environment and demo in the file:
    # the file must win.
    r = get("conflict", "/", base=MIXED_URL)
    assert r.status_code == 200
    assert "DEMO-OK" in r.text
    assert "LOCALSERVER-OK" not in r.text
