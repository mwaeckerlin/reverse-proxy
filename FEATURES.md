# Features

Numbered register of every feature; a number is never reused. Every feature is covered by tests listed in [TESTS.md](TESTS.md); the guard `tests/docs-contract.sh` fails when a feature has no test.

- **F1 — Forward by host and path.** A request is forwarded by its host name, and optionally a base path, to an internal service `host`, `host:port` or `[scheme://]host:port/base`; each host reaches only its own backend.
- **F2 — Permanent redirect.** A host, optionally with a base path, is redirected permanently to a public URL; other paths of the host are not affected.
- **F3 — www to the bare host.** A request to `www.<domain>` is redirected to `<domain>`.
- **F4 — Rules from the environment.** `FORWARD` and `REDIRECT` hold one rule `<source> <target>` per line and are applied at container start, without a rebuild.
- **F5 — Rules from a file.** `/config/reverse-proxy.conf` holds rules with the verb as first word; blank lines and `#` comments are ignored.
- **F6 — Both sources combined.** Rules of the environment and of the file are merged; for the same host the file wins.
- **F7 — Reload on change.** A change of the configuration file or of a certificate under `/etc/letsencrypt/live` reloads nginx at once.
- **F8 — Invalid rules ignored.** A rule with characters outside letters, digits and `._:/-` is ignored with a warning; every other rule stays in effect.
- **F9 — Not found and maintenance pages.** An unconfigured host answers with the not found page, a configured host whose backend does not answer with the maintenance page (502).
- **F10 — Basic authentication.** A htpasswd file `/etc/nginx/basic-auth/<host>.htpasswd` (or `<host>/<base>.htpasswd`) protects the host; the realm is the host name, or `BASIC_AUTH_REALM`. A realm with characters outside letters, digits, space and `._:/-@(),` is ignored with a warning, so it can never close the directive and switch the protection off.
- **F11 — Backend redirects rewritten.** A redirect of the backend to its internal address is rewritten to the public host; `PROXY_REDIRECT_OFF` lists the `host[/base]` entries that pass it unchanged.
- **F12 — Security headers.** `Referrer-Policy: no-referrer` and `X-Content-Type-Options: nosniff` are set exactly once on forwarded responses, replacing a copy of the backend; HTTPS responses carry `Strict-Transport-Security` for one year.
- **F13 — HTTPS with Let's Encrypt.** With a certificate in `/etc/letsencrypt/live` the host is served over HTTPS on 8443 with that certificate, and HTTP redirects to HTTPS; the ACME challenge is answered from `/acme` for `mwaeckerlin/letsencrypt`.
- **F14 — DH parameters at first start.** The Diffie-Hellman parameters are generated at the first start with `DHPARAM` bits (default 4096) and kept on `DHPARAM_FILE`; a file already there is used as it is.
- **F15 — Starts by its default command.** The container boots without a `command` override, listening on 8080 and 8443.
- **F16 — Headless.** Only `nginx`, `inotifywait` and the program `run-nginx` are in the image: no shell, no interpreter.
- **F17 — Published for amd64 and arm64.** Every push builds the image natively for both architectures and publishes it under one tag on Docker Hub, with the reusable workflow of `mwaeckerlin/scratch`.
