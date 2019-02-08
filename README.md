Docker Image: Virtual Hosts Reverse Proxy
=========================================

Ports
-----

This reverse proxy listens on ports `8000` for HTTP and `8443` for HTTPS.

Configuration From Config File
------------------------------

You can reference a file with name `reverse-proxy.conf`. In directry, e.g. `config` create a configuration named `reverse-proxy.conf` that contains lines with redirect and forward configurations in the form as they are accepted by the script `nginx-configure.sh`. Try `nginx-configure.sh --help` for more information. You can then use it as mount or volume.

The best of all: If the config file is used and it changes while the reverse proxy is running, nginx is reconfigured and the new configuration is reloaded without downtime.

Example for a `reverse-proxy.conf` file:

```
--redirect my.web-site.com  my.website.com
--forward  my.website.com   server1.intranet:8001
--forward  another.site.com server2.intranet:8080
--forward  some.more.com    192.168.16.8
```

Mount the directory that contains `config` into `/config` of the docker container. If you volume in a container, you can change it dynamically from outside, in this example, file `reverse-proxy.conf` is in directory `config`:
```
docker run -d -v $(pwd)/config:/config … mwaeckerlin/reverse-proxy
```

Best, use it as mount in a swarm service, so you can change it dynamically from outside:
```
docker service create -d --mount type=bind,source=$(pwd)/config,target=/confic … mwaeckerlin/reverse-proxy
```

In case of conflicts, docker `--link` and `--environment` configurations overwrite the configurations from `reverse-proxy.conf`, so better don't mix.


Generic Configuration and Secret Files
--------------------------------------

Any configuration or secret file that ends in `*.conf.sh` is sourced
at startup, so you can add your environment variables into these
configurations or secret files.

E.g.:

```
docker secret create env.conf.sh - <<EOF
export MY_SPECIAL_PASSWORD="S3cr37p@ßvv0Rð"
EOF
docker config create env.conf.sh - <<EOF
export LOG_LEVEL="debug"
export MAILCONTACT="me@home.com"
export LETSENCRYPT="off"
EOF
```


Redirect URL to Linked Container
--------------------------------

On your computer start any number of services, then start a `mwaeckerlin/reverse-proxy` and link to all your docker services. The link alias must be the FQDN, the fully qualified domain name of your service. For example your URL is `wordpress.myhost.org` and wordpress runs in a docker container named `mysite`:

        docker run [...] -l mysite:wordpress.myhost.org mwaeckerlin/reverse-proxy


If a Service Has More Than One Port
-----------------------------------

Normally the port is detected automatically. But if there are more than one open ports, you must declare which port you want to direct to. Jenkins for example exposes the ports 8080 and 5000. You want to forward to port 8080. For this you specify an additional environment variable that contains the URL in upper case, postfixed by `_TO_PORT`, e.g. redirect URL `jenkins.myhost.org` to port 8080 of container `jenkins`:

        docker run [...] -l jenkins:jenkins.myhost.org -e JENKINS.MYHOST.ORG_TO_PORT=8080 mwaeckerlin/reverse-proxy


Forward or Redirect to Other Host
---------------------------------

In addition, you can add environment variables that start with `redirect-` or `forward-` for an additional redirect or an additional forward, e.g. the following redirects from your old host at `old-host.com` to your new host at `new-host.org`, similary `-e forward-old-host.com=new-host.org` adds a forward:

        docker run [...] -e redirect-old-host.com=new-host.org mwaeckerlin/reverse-proxy

For special characters in the variable name (not in the value) use hexadecimal ASCII code, as in URL encoding, so if you need to append a path, use `%2f` instead of slash `/` in the path.


Don't Write Proxy-Redirect
--------------------------

By default, nginx variable `proxy_redirect` is configured automatically. If you don't want this and if you want `proxy_redirect off`, then set environment variable `PROXY_REDIRECT_OFF` to a space separated list of urls (just host and path, without scheme) with this configuration. When I tried to install [NodeBB](https://nodebb.org), I noticed that they require this configuartion. Example:

    docker run [...] -e PROXY_REDIRECT_OFF='forum.example.com other.forum.org/path' mwaeckerlin/reverse-proxy


The Dummy-www-Prefix
--------------------

Rules to redirect the dummy-www-prefix to the host without prefix are automatically added, so don't prepend `www.` to your hostnames.


SSL Certificates
----------------

By default the reverse proxy automatically gets new SSL certificates from [Let's Encrypt](https://letsencrypt.org/), unless you configure `LETSENCRYPT=off`

Configuration:

 - `MAILCONTACT`: mailcontact for Let's Encrypt, configure as one of these:
     - _`user`_`@`_`host.url`_: all mails for all domains go to one account `user@host.url`
     - _`user`_: one account per SSL domain, mails go to account `user@domain.url` where `domain.url` is the URL of your SSL domain
     - _empty_: do not register an email address
 - `LETSENCRYPT`: Set environment variable `LETSENCRYPT` to:
     - `on`: use `https` all certificates are installed using Let's Encrypt (default)
     - `off`: do not use `https`

So, if you don't care, all your sites will automatically be encrypted.


Basic Authentication
--------------------

Enable basic authentication for a server by adding a file named `/etc/nginx/basic-auth/${server}.htpasswd`, where `${server}` is the name of the server, e.g. add `/etc/nginx/basic-auth/example.com.htpasswd`. The file must contain an apache compatible password file. This file can be created e.g. using `htpasswd /etc/nginx/basic-auth/example.com.htpasswd username`.

To only restrict access in a configured sub-path, or to have different users in a sub-path, you can create a file in `/etc/nginx/basic-auth/${server}/${basepath}.htpasswd`, e.g. `/etc/nginx/basic-auth/example.com/private.htpasswd`. The sub-path is only evaluated, if it appears in a forward or redirect configuration.

The realm is either the server/sub-path name or you can overwrite it in variable `BASIC_AUTH_REALM`.


More Configurations
-------------------

The following additional environment variables can be configured:
 - `DEBUG_LEVEL`: set debug level to one of: `debug`, `info`, `notice`, `warn`, `error`, `crit`, `alert`, `emerg`


Examples
--------

### Example ###

  1. Start a wordpress instance (including a volume container):

        docker run -d --name test-volumes --volume /var/lib/mysql --volume /var/www/html ubuntu sleep infinity
        docker run -d --volumes-from test-volumes --name test-mysql -e MYSQL_ROOT_PASSWORD=$(pwgen -s 16 1) mysql
        docker run -d --volumes-from test-volumes --name test-wordpress --link test-mysql:mysql wordpress
  2. Start any number of other services ...
  3. Start a `reverse-proxy`: 

        docker run -d --restart=always --name reverse-proxy \
          --link test-wordpress:test.mydomain.com \
          -p 80:80 mwaeckerlin/reverse-proxy
  4. Head your browser to `https://test.mydomain.com`

### Other Example ###

  1. Situation:
      1. `hosta` in local network is public visible through `https://host.com`
      2. There is a `mwaeckerlin/dokuwiki` in a docker container on `hosta`
      3. There is a `mwaeckerlin/jenkins` running on `hostb` with opened port `8080`
      4. `https://host.com` is public in internet
      5. There is a SSL-certificate (in P12 format) for `host.com` named `host.com.p12`
  2. Requirements:
      1. There should be a default redirection from `https://host.com` to `https://host.com/dokuwiki`
      2. There should be a forwarding from `https://host.com/dokuwiki` to local container `dokuwiki`
      3. There should be a forwarding from `https://host.com/jenkins` to container `jenkins` that is exposed on port `8080` on `hostb`
  3. Configuration
      1. Create `host.com.crt` and an unencrypted `host.com.key` from `host.com.p12`: 

            ```bash
            openssl pkcs12 -in host.com.p12 -nocerts -out host.com.pem
            openssl rsa -in host.com.pem -out host.com.key
            openssl pkcs12 -in host.com.p12 -nokeys -out host.com.crt
            rm host.com.pem
            ```
      2. Create a docker volume containing the keys: 

            ```bash
            cat > Dockerfile <<EOF
            FROM mwaeckerlin/reverse-proxy
            VOLUME /etc/ssl
            ADD host.com.crt /etc/ssl/host.com.crt
            ADD host.com.key /etc/ssl/host.com.key
            CMD sleep infinity
            EOF
            docker build --rm --force-rm -t reverse-proxy-volume .
            rm Dockerfile
            ```
      3. Instanciate the volume and the reverse-proxy container 

            ```bash
            docker run -d --name reverse-proxy-volume reverse-proxy-volume
            docker run -d --name reverse-proxy \
              --volumes-from reverse-proxy-volume \
              -e redirect-host.com=host.com/dokuwiki \
              --link dokuwiki:host.com/dokuwiki \
              -e forward-host.com%2fjenkins=hostb:8080 \
              -p 80:80 -p 443:443 mwaeckerlin/reverse-proxy
            ```
