# Docker Image: Virtual Hosts Reverse Proxy

This is a reverse proxy that listens for HTTP and HTTPS on a single incoming port, then redirects according to the URL, namely the domain name and/or path to any internal, not globally visible server. This is for use in a cloud, such as docker swarm or kubernetes.

For using SSL, the service expects SSL-Certificates in `/etc/letsencrypt/live`, so you should run [mwaeckerlin/letsencrypt](https://github.com/mwaeckerlin/letsencrypt) in a seperate container and redirext all requests to `/.well-known` to there and mount a common `/etc/letsencrypt/live`. If a file in `/etc/letsencrypt/live` changes, then the reverse proxy is reloaded immediately and uses the new certificates.

The image is highly optimized, there are only three executables in the image: `nginx` the webserver, `inotifywait` to check for new certificates and a small C++ program `run-nginx` to coordinate those two. There is no shell in the container. So the image is around 10MB including your configurations.

**NOTE:** Configuration has changed. Users of the previous version need to migrate. Configuration is now generated at build time and included in the image. Instead of configuration by file , variables or container link analysis, configuration is now done by two build arguments.

## Ports

This reverse proxy listens on ports `8080` for HTTP and `8443` for HTTPS.

## Configuration

There are two ways the reverse proxy works:

- forwarding requests to another service
- redirect the url to another location

Configuration has to be done at build time, so just fork or clone the project, then write your own `docker-compose.yaml` with your configuration.

### SSL

Build time argument `SSL` can be set to `off` to disable `https`.

### Forwarding Requests

Build time argument `FORWARD` configures urls to be forwarded. Each definituion consists of a external from URL and an internal to URL and must be an a separate line, separated by newline.

### Redirecting URLs

### Example

This is a snipped from `docker-compose.yaml`:

    reverse-proxy:
      image: mwaeckerlin/reverse-proxy
      ports:
         - 8080:8080
      build:
         context:
         args:
            SSL: "off"
            FORWARD: |-
               localhost localserver:8080
               demo demo:8080
               test test:8080
               lokal lokal:8080
               doesnotrun doesnotrun:8080
            REDIRECT: |-
               extern pacta.swiss

SSL is disabled for simplicity.

Requests on [http://localhost:8080] (port from `ports:`) are forwarded to port `8080` of service `localserver`. Requests to [http://demo:8080] are forwarded to port `8080` of service `demo`. And so on.

Requests to [http://extern:8080] are redirected to [http://pacta.swiss].

Service `doesnotrun` is not configured, so a call to [http://doesnotrun:8080] shows the maintenance page.

Service `lokal` is not configured, so a call to [http://lokal:8080] shows the not found page.

#### Build and Run the Sample

To be able to locally browse to [http://demo:8080], add to line `127.0.0.1 localhost` your `/etc/hosts` new host names, namely `demo`, `test`, `lokal`, `extern` and `doesnotrun`:

    127.0.0.1	localhost demo test lokal extern doesnotrun

Then build and run the example from `docker-compose.yaml`:

- `docker-compose build`
- `docker-compose up`
- browse to:
  - [http://localhost:8080]
  - [http://demo:8080]
  - [http://test:8080]
  - [http://lokal:8080] - not found error
  - [http://doesnotrun:8080] - shows maintenance page
  - [http://extern:8080]
- hit `ctrl+c` when done
