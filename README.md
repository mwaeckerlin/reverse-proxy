# Docker Image: Virtual Hosts Reverse Proxy

## Redirect URL to Linked Container

On your computer start any number of services, then start a `mwaeckerlin/reverse-proxy` and link to all your docker services. The link alias must be the FQDN, the fully qualified domain name of your service. For example your URL is `wordpress.myhost.org` and wordpress runs in a docker container named `mysite`:

        docker run [...] -l mysite:wordpress.myhost.org mwaeckerlin/reverse-proxy

## If a Service Has More Than One Port

Normally the port is detected automatically. But if there are mre than one open porrs, you must declare which port you want to direct to. Jenkins for example exposes the ports 8080 and 5000. You want to forward to port 8080. For this you specify an additional environment variable that contains the URL in upper case, postfixed by `_TO_PORT`, e.g. redirect URL `jenkins.myhost.org` to port 8080 of container `jenkins`:

        docker run [...] -l jenkins:jenkins.myhost.org -e JENKINS.MYHOST.ORG_TO_PORT=8080 mwaeckerlin/reverse-proxy

## Forward or Redirect to Other Host

In addition, you can add environment variables that start with `redirect-` or `forward-` for an additional redirect or an additional forward, e.g. the following redirects from your old host at `old-host.com` to your new host at `new-host.org`, similary `-e forward-old-host.com=new-host.org` adds a forward:

        docker run [...] -e redirect-old-host.com=new-host.org mwaeckerlin/reverse-proxy

For special characters use hexadecimal ASCII code, as in URL encoding, so if you need to append a path, use `%2f` instead of slash `/` in the path.

## SSL Certificates

## The Dummy-www-Prefix

Rules to redirect the dummy-www-prefix to the host without prefix are automatically added, so don't prepend `www.` to your hostnames.

## Example

Example:

  1. Start a wordpress instance (including a volume container): 

        docker run -d --name test-volumes --volume /var/lib/mysql --volume /var/www/html ubuntu sleep infinity
        docker run -d --volumes-from test-volumes --name test-mysql -e MYSQL_ROOT_PASSWORD=$(pwgen -s 16 1) mysql
        docker run -d --volumes-from test-volumes --name test-wordpress --link test-mysql:mysql wordpress
  2. Start any number of other services ...
  3. Start a `reverse-proxy`

        docker run -d --restart=always --name reverse-proxy --link test-wordpress:test.mydomain.com -p 80:80 mwaeckerlin/reverse-proxy
  4. Head your browser to http://test.mydomain.com
