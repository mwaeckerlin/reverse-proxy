# Changelog

- 2026-09-26 **2.0.4**
    - Includes letsencrypt 2.0.3, whose end to end test no longer fails when the second certificate is issued a moment later

- 2026-09-26 **2.0.3**
    - The test suite installs its Python packages without a warning

- 2026-09-26 **2.0.2**
    - Security: a realm name in `BASIC_AUTH_REALM` that closed the quote could switch the password protection off; such a realm is now ignored with a warning and the host name serves as realm
    - The image is published for amd64 and arm64 under one tag, built and published automatically on every change and every week

- 2026-07-17 **2.0.1**
    - Hardening after a static security review:
        - Malformed or hostile forward/redirect rules are rejected with a warning instead of being written into the web server configuration, so one bad rule can no longer take all virtual hosts down.
        - Proxied responses now carry exactly one `Referrer-Policy` and one `X-Content-Type-Options: nosniff` header, replacing backend copies.
        - The HSTS lifetime is raised to one year.
    - The demo compose file configures the routing at runtime again (build arguments stopped working with 2.0.0) and no longer suggests weak Diffie-Hellman parameters.
    - The image build context is reduced to the files the image needs; the image build and the test suites run without warnings.

- 2026-07-16 **2.0.0**
    - Configuration is applied again when the container starts, not when the image is built — you no longer rebuild the image to change the routing.
        - Rules are read from the environment variables `FORWARD` and `REDIRECT` and/or from a mounted file `/config/reverse-proxy.conf`.
        - Both sources are combined; if the same host is defined in both, the file wins.
        - The configuration file is watched and applied immediately on change, the same way certificate changes are.
    - Simplified configuration file syntax: the `--forward` / `--redirect` prefix is dropped; write `forward …` / `redirect …`.
    - Forwarded hosts can again be protected with HTTP basic authentication by mounting a htpasswd file under `/etc/nginx/basic-auth`.
    - New certificates and renewals are now detected reliably, including newly added domains, and applied without downtime.
    - The Diffie-Hellman parameters are generated once when the container first starts (strong by default) and kept, instead of a weak placeholder baked into the image; a ready-made file can be provided to skip generation.
    - The proxy shuts down cleanly when the container is stopped.
    - The companion certificate image (mwaeckerlin/letsencrypt) is now headless (lego instead of certbot); it keeps publishing certificates under `/etc/letsencrypt/live/<domain>/`, so the proxy needs no change.
    - Migration notes for existing deployments:
        - Remove the `--` prefix from the configuration file.
        - Move the forward/redirect rules from build arguments to the `FORWARD`/`REDIRECT` environment variables or the configuration file.
        - Remove any `command: /start.sh` override; the container starts on its own.
        - Map the public ports to the container ports `8080` and `8443`, e.g. `80:8080` and `443:8443`.
