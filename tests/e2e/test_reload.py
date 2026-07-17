"""Live reload: the configuration file is watched like the certificates, so
editing it reconfigures nginx without a restart.

The proxy revproxy-reload mounts an initially empty shared volume at /config;
this test writes /reload-config/reverse-proxy.conf (the same volume) and checks
that the proxy picks up the route, then rewrites it and checks the route
changes -- proving the file watch triggers a reload.
"""
from conftest import RELOAD_URL, get, wait_until

CONFIG = "/reload-config/reverse-proxy.conf"


def _write(rule: str) -> None:
    with open(CONFIG, "w") as f:
        f.write(rule + "\n")


def _body_for(host: str):
    def check():
        try:
            r = get(host, "/", base=RELOAD_URL)
        except Exception:
            return None
        return r.text if r.status_code == 200 else None
    return check


def test_config_file_change_reloads_route():
    # Initially there is no route for reloadhost.
    assert get("reloadhost", "/", base=RELOAD_URL).status_code == 404

    # Adding a forward must make the route appear after the file watch reload.
    _write("forward reloadhost localserver:8080")
    body = wait_until(lambda: _body_for("reloadhost")())
    assert body is not None and "LOCALSERVER-OK" in body

    # Changing the target must be picked up too.
    _write("forward reloadhost demo:8080")
    body = wait_until(
        lambda: (lambda t: t if t and "DEMO-OK" in t else None)(_body_for("reloadhost")())
    )
    assert body is not None and "DEMO-OK" in body

    # Removing the rule must drop the route again: the previously generated
    # server block has to be cleaned up on reload.
    _write("")
    gone = wait_until(
        lambda: get("reloadhost", "/", base=RELOAD_URL).status_code == 404
    )
    assert gone, "route was not removed after the rule was deleted"
