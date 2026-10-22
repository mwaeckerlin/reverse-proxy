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

Without a mounted file, the environment variable `BASIC_AUTH` holds one entry per line, `<host>[/<base>] <user>:<password hash>`, in the format of a htpasswd line; several lines with the same host give several users. `BASIC_AUTH_FILE` names a file with the same content, such as a docker secret, and its entries are added to those of `BASIC_AUTH`. An entry for a base path wins over the entry of its host; for the same host and base a mounted htpasswd file wins over the entries. Create the hash with `htpasswd -nB <user>`, and write every `$` of the hash as `$$` in a compose file:

```yaml
environment:
  BASIC_AUTH: |-
    example.com        alice:$$2y$$05$$...
    example.com/admin  bob:$$2y$$05$$...
```

An entry whose host has other characters than letters, digits and `._:/-`, contains `..`, or whose second word is not `<user>:<hash>` is ignored with a warning in the container log that names the host and never the hash.

Basic authentication protects only over HTTPS. Until the certificate exists (or with `SSL=off`) the host is served over plain HTTP and credentials would travel unencrypted, so protect a host once it is served over HTTPS.

### Other environment variables

- `PROXY_REDIRECT_OFF`: whitespace separated list of `host[/base]` for which nginx `proxy_redirect` is turned off. By default, a redirect of the backend to its internal address (`Location: http://backend:8080/x/`) is rewritten to the public host (`http://<host>:8080/x/`); for the listed entries the header passes unchanged.
- `CLIENT_MAX_BODY_SIZE`: largest request body, default `0` for no limit; a larger body answers 413.
- `CLIENT_BODY_BUFFER_SIZE`: memory buffer for a request body before nginx writes it to a temporary file, default `128k`.
- `PROXY_BUFFERS`: number and size of the buffers for a backend response, as nginx `proxy_buffers`, default `32 4k`.
- `PROXY_CONNECT_TIMEOUT`: time to connect to a backend, default `1200` seconds.
- `PROXY_READ_TIMEOUT`: time a backend may stay silent while answering, default `86400` seconds; a backend that takes longer gets the 504 page.
- `PROXY_SEND_TIMEOUT`: time a backend may take to read the forwarded request, default `1200` seconds.
- `SEND_TIMEOUT`: time a client may take to read the response, default `1200` seconds.
- `WORKER_CONNECTIONS`: connections per nginx worker, default `1024`.
- `KEEPALIVE_TIMEOUT`: how long an idle client connection stays open, default `65` seconds.
- `HSTS_MAX_AGE`: lifetime of `Strict-Transport-Security` in seconds, default `31536000` (one year); `0` tells browsers to forget the HSTS of the host.

Times are seconds, or carry an nginx unit (`ms`, `s`, `m`, `h`, `d`, `w`, `M`, `y`); sizes are bytes, or carry `k`, `m` or `g`. An empty variable takes the default; a value of another form is replaced by the default with a warning in the container log, so it can neither stop the proxy nor add a directive to its configuration.

### Security trade-offs

- **No request size limit** (`CLIENT_MAX_BODY_SIZE=0`): uploads of any size reach the backend, as cloud applications need it; a client can fill the temporary space of the proxy. Set a limit where no backend takes large uploads.
- **Long timeouts** (`PROXY_READ_TIMEOUT=86400`, `PROXY_CONNECT_TIMEOUT`, `PROXY_SEND_TIMEOUT` and `SEND_TIMEOUT` `1200`): long running requests and WebSockets stay open for a day; slow clients and backends hold connections that long. Lower them where no backend needs it.

### Security headers

The proxy is authoritative for two response headers on forwarded requests: `Referrer-Policy: no-referrer` and `X-Content-Type-Options: nosniff` are set exactly once, replacing any backend copy. HTTPS responses carry `Strict-Transport-Security` with the lifetime `HSTS_MAX_AGE`, one year by default.

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

The image ships an end-to-end test suite driven by pytest against a real `docker compose` stack (`tests/e2e/`), an HTTPS suite with a local ACME server (`tests/e2e-https/`), a headless-image contract check (`tests/image-contract.sh`), the check of the configuration rendered from the environment (`tests/config-contract.sh`) and the check of the feature register ([FEATURES.md](FEATURES.md), [TESTS.md](TESTS.md)). The image is built and published for `linux/amd64` and `linux/arm64` by the reusable workflow of [mwaeckerlin/scratch](https://github.com/mwaeckerlin/scratch#publishing-on-docker-hub). Run everything with:

```bash
npm test
```
