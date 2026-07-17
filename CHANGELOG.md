# Changelog

- 2026-07-16 **2.0.0**
    - Configuration is applied again when the container starts, not when the
      image is built — you no longer rebuild the image to change the routing.
        - Rules are read from the environment variables `FORWARD` and `REDIRECT`
          and/or from a mounted file `/config/reverse-proxy.conf`.
        - Both sources are combined; if the same host is defined in both, the
          file wins.
        - The configuration file is watched and applied immediately on change,
          the same way certificate changes are.
    - Simplified configuration file syntax: the `--forward` / `--redirect`
      prefix is dropped; write `forward …` / `redirect …`.
    - Forwarded hosts can again be protected with HTTP basic authentication by
      mounting a htpasswd file under `/etc/nginx/basic-auth`.
    - New certificates and renewals are now detected reliably, including newly
      added domains, and applied without downtime.
    - The Diffie-Hellman parameters are generated once when the container first
      starts (strong by default) and kept, instead of a weak placeholder baked
      into the image; a ready-made file can be provided to skip generation.
    - The proxy shuts down cleanly when the container is stopped.
    - The companion certificate image (mwaeckerlin/letsencrypt) is now headless
      (lego instead of certbot); it keeps publishing certificates under
      `/etc/letsencrypt/live/<domain>/`, so the proxy needs no change.
    - Migration notes for existing deployments:
        - Remove the `--` prefix from the configuration file.
        - Move the forward/redirect rules from build arguments to the
          `FORWARD`/`REDIRECT` environment variables or the configuration file.
        - Remove any `command: /start.sh` override; the container starts on its
          own.
        - Map the public ports to the container ports `8080` and `8443`, e.g.
          `80:8080` and `443:8443`.
