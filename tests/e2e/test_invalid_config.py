"""Invalid rules: a malformed forward/redirect token must never take the proxy
down, must not create a route, and must not stop later valid rules.

The environment of the reverse-proxy service deliberately contains invalid
rules (``bad{host``, ``bad;redir``) followed by a valid one (``after.invalid``):
the proxy must ignore the invalid rules with a warning and still serve every
other configured host. Without validation a single such token breaks the
generated nginx configuration and takes every virtual host down at start.
"""
from conftest import get


def test_valid_rule_after_invalid_is_served():
    # The rule after the invalid ones must still be applied.
    r = get("after.invalid", "/")
    assert r.status_code == 200
    assert "LOCALSERVER-OK" in r.text


def test_invalid_forward_creates_no_route():
    r = get("bad{host", "/")
    assert r.status_code == 404


def test_other_hosts_unaffected_by_invalid_rules():
    r = get("localhost", "/")
    assert r.status_code == 200
    assert "LOCALSERVER-OK" in r.text
