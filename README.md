# Docker Image: Virtual Hosts Reverse Proxy

This is a reverse proxy that listens for HTTP and HTTPS on a single incoming port, then redirects according to the URL, namely the domain name and/or path, to any internal, not globally visible server. This is for use in a cloud, such as docker swarm or kubernetes.

For using SSL, the service expects SSL-Certificates in `/etc/letsencrypt/live`, so you should run [mwaeckerlin/letsencrypt](https://github.com/mwaeckerlin/letsencrypt) in a separate container, redirect all requests to `/.well-known` to there and mount a common `/etc/letsencrypt/live`. If a file in `/etc/letsencrypt/live` changes, the reverse proxy is reloaded immediately and uses the new certificates.

The image is highly optimized: there are only three executables in the image — `nginx` the webserver, `inotifywait` to watch for changes, and a small C++ program `run-nginx` that renders the configuration from the environment and the optional configuration file, starts nginx, and reloads it whenever the configuration or the certificates change. There is no shell in the container, so the image is around 10 MB including your configuration.

## Configuration

The reverse proxy does two things:

- **forward** a request to another (cloud-internal) service, or
- **redirect** a URL to another (public) location.

Configuration is applied **at instantiation** (container start) — nginx itself cannot be configured from environment variables, `run-nginx` renders the nginx configuration for it. You do **not** need to rebuild the image to change the routing.

There are two configuration sources, and they can be combined:

1. The environment variables `FORWARD` and `REDIRECT`.
2. A mounted configuration file `/config/reverse-proxy.conf`.

Both sources are merged. If the same source host is defined in both, the **file wins**. The configuration file is watched: editing it reloads nginx automatically, just like a certificate change.

### Environment variables

`FORWARD` and `REDIRECT` each contain one rule per line, `<source> <target>`:

```yaml
environment:
  FORWARD: |-
    localhost      localserver:8080
    example.com    backend:4000
  REDIRECT: |-
    old.example.com   example.com
```

### Configuration file

`/config/reverse-proxy.conf` holds one rule per line, with the verb as the first word (blank lines and `#` comments are ignored):

```text
forward   localhost     localserver:8080
forward   example.com   backend:4000
redirect  old.example.com   example.com
```

### Source and target format

- **source**: the externally visible domain name with an optional base path, `domain` or `domain/base`. Requests to `www.<domain>` are redirected to `<domain>`.
- **target** of a forward: an internal host with optional scheme, port and base path, `host`, `host:port` or `[scheme://]host:port/base`. The target is usually not public, only reachable inside the cloud.
- **target** of a redirect: the public URL to redirect to.

Rule tokens are validated: only letters, digits and `._:/-` are accepted, and the host part must not be empty. An invalid rule is ignored with a warning in the container log; all other rules stay in effect.

An unconfigured host answers with the *not found* page; a configured forward whose backend is unreachable answers with the *maintenance* page.

### Basic authentication

To protect a forwarded host with HTTP basic-auth, mount a htpasswd file at `/etc/nginx/basic-auth/<host>.htpasswd` (or `/etc/nginx/basic-auth/<host>/<base>.htpasswd` for a specific base path). When present, `run-nginx` wires it up automatically. The realm is the host name and can be overridden with the environment variable `BASIC_AUTH_REALM`. The realm may contain letters, digits, spaces and `._:/-@(),`; any other character could end the directive, so such a realm is ignored with a warning in the container log and the host name is used.

Basic authentication protects only over HTTPS. Until the certificate exists (or with `SSL=off`) the host is served over plain HTTP and credentials would travel unencrypted, so protect a host once it is served over HTTPS.

### Other environment variables

- `PROXY_REDIRECT_OFF`: whitespace separated list of `host[/base]` for which nginx `proxy_redirect` is turned off. By default, a redirect of the backend to its internal address (`Location: http://backend:8080/x/`) is rewritten to the public host (`http://<host>:8080/x/`); for the listed entries the header passes unchanged.

### Security headers

The proxy is authoritative for two response headers on forwarded requests: `Referrer-Policy: no-referrer` and `X-Content-Type-Options: nosniff` are set exactly once, replacing any backend copy. HTTPS responses carry `Strict-Transport-Security` with a lifetime of one year.

## Ports

The reverse proxy listens on port `8080` for HTTP and `8443` for HTTPS. Map them to the public ports in your compose file, e.g. `80:8080` and `443:8443`.

## Migration from the previous versions

- The old versions passed rules **on the command line / in a file** with a `--` prefix (`--forward …`, `--redirect …`). The prefix is **gone**: in the file, write `forward …` / `redirect …` without `--`.
- The intermediate version configured the rules as **build arguments** and baked them into the image. Configuration is now done again **at runtime** via the `FORWARD`/`REDIRECT` environment variables and/or the `/config/reverse-proxy.conf` file — no image rebuild is needed to change the routing.
- The container now boots via its default command; a `command: /start.sh` override from an old deployment must be removed.
- Ports are `8080`/`8443` inside the container — map `80:8080` and `443:8443`.

## Example

A minimal HTTP-only stack (SSL omitted for simplicity):

```yaml
services:
  reverse-proxy:
    image: mwaeckerlin/reverse-proxy
    ports:
      - 8080:8080
    environment:
      FORWARD: |-
        localhost   localserver:8080
        demo        demo:8080
        doesnotrun  doesnotrun:8080
      REDIRECT: |-
        extern      example.com

  localserver:
    image: mwaeckerlin/nginx
  demo:
    image: mwaeckerlin/nginx
  # not a web server -> the maintenance page is shown for `doesnotrun`
  doesnotrun:
    image: mwaeckerlin/very-base
    command: ["sleep", "infinity"]
```

Requests to `localhost` and `demo` are forwarded to the respective backends, `extern` is permanently redirected to `example.com`, and `doesnotrun` shows the maintenance page.

## SSL with Let's Encrypt

[mwaeckerlin/reverse-proxy](https://github.com/mwaeckerlin/reverse-proxy) and [mwaeckerlin/letsencrypt](https://github.com/mwaeckerlin/letsencrypt) share the volumes for the `/acme` challenge and the certificates in `/etc/letsencrypt`. When a certificate appears or is renewed under `/etc/letsencrypt/live`, the reverse proxy reloads and serves it. Restart [mwaeckerlin/letsencrypt](https://github.com/mwaeckerlin/letsencrypt) at most once per hour, because too many failed attempts block the account.

### DH parameters

The Diffie-Hellman parameters are generated at the first container start (not baked into the image) with `DHPARAM` bits (default `4096`) and kept on `DHPARAM_FILE` (default `/etc/letsencrypt/dhparam.pem`), so they are generated only once. The first start therefore takes a while; provide a ready-made file at `DHPARAM_FILE` (or a smaller `DHPARAM`) to skip or speed up generation.

Because Let's Encrypt must write into `/etc/letsencrypt` and `/acme`, but volumes created by `docker compose` cannot be assigned an owner, the service `fix-permission` starts up once and assigns the paths to `${RUN_USER}` by running `${ALLOW_USER}` (defined as `chown -R ${RUN_USER}:${RUN_GROUP}` in [mwaeckerlin/scratch](https://github.com/mwaeckerlin/scratch)).

```yaml
services:
  fix-permission:
    image: mwaeckerlin/very-base
    command:
      - '/bin/sh'
      - '-c'
      - '$${ALLOW_USER} /etc/letsencrypt /acme'
    volumes:
      - type: volume
        source: certificates
        target: /etc/letsencrypt
      - type: volume
        source: acme
        target: /acme

  reverse-proxy:
    image: mwaeckerlin/reverse-proxy
    depends_on:
      - fix-permission
    ports:
      - '80:8080'
      - '443:8443'
    environment:
      FORWARD: |-
        example-service.example.com example-service:4000
    networks:
      - proxy-letsencrypt
      - proxy-example-service
    volumes:
      - type: volume
        source: certificates
        target: /etc/letsencrypt
      - type: volume
        source: acme
        target: /acme

  letsencrypt:
    image: mwaeckerlin/letsencrypt
    depends_on:
      - fix-permission
      - reverse-proxy
    environment:
      EMAIL: 'marc@example.com'
      DOMAINS: 'example-service.example.com'
      PREFIXES: ''
    networks:
      - proxy-letsencrypt
    volumes:
      - type: volume
        source: certificates
        target: /etc/letsencrypt
      - type: volume
        source: acme
        target: /acme
    deploy:
      restart_policy:
        condition: on-failure
        delay: 1h

  example-service:
    image: example-service
    networks:
      - proxy-example-service

volumes:
  certificates: {}
  acme: {}
networks:
  proxy-letsencrypt:
  proxy-example-service:
```

## Tests

The image ships an end-to-end test suite driven by pytest against a real `docker compose` stack (`tests/e2e/`), an HTTPS suite with a local ACME server (`tests/e2e-https/`), a headless-image contract check (`tests/image-contract.sh`) and the check of the feature register ([FEATURES.md](FEATURES.md), [TESTS.md](TESTS.md)). The image is built and published for `linux/amd64` and `linux/arm64` by the reusable workflow of [mwaeckerlin/scratch](https://github.com/mwaeckerlin/scratch#publishing-on-docker-hub). Run everything with:

```bash
$ npm test
```
