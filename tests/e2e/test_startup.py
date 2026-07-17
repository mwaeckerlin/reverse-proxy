"""Startup regression: the proxy must boot via its own default command.

Production regression (2026-07-09): the swarm service started the container
with the legacy command ``/start.sh``. The image dropped that shell script in
the 2023 rewrite (commit e944950) -- its ``CMD`` is now ``/usr/bin/run-nginx``
-- so the container died with::

    exec: "/start.sh": stat /start.sh: no such file or directory

This test locks in that the image boots and serves HTTP through its own default
entrypoint. If any deployment pins ``/start.sh`` (or any other missing command)
again, the proxy never comes up and this test fails at readiness.
"""
from conftest import REVPROXY_URL, get, wait_for_proxy


def test_proxy_boots_via_default_command():
    # Started with the obsolete /start.sh command the container would
    # crash-loop and never answer here.
    wait_for_proxy(REVPROXY_URL)
    r = get("localhost", "/", allow_redirects=False)
    assert r.status_code == 200
    assert "LOCALSERVER-OK" in r.text
