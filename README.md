# Docker Image: Virtual Hosts Reverse Proxy

On your computer start any number of services, then start a `mwaeckerlin/reverse-proxy` and link to all your docker services. The link alias must be the FQDN, the fully qualified domain name of your service.

In addidion, you can add environment variables that start with `redirect-` or `forward-` for an additional redirect or an additional forward, e.g. the following redirects from your old host at `old-host.com` to your new host at `new-host.org`, similary `-e forward-old-host.com=new-host.org` adds a forward:

        docker run -d -e redirect-old-host.com=new-host.org reverse-proxy

For special characters use hexadecimal ASCII code, as in URL encoding, so if you need to append a path, use `%2f` instead of slash `/` in the path.

Rules to redirect the dummy-www-prefix to the host without prefix are automatically added, so don't prepend `www.` to your hostnames.

Example:

  1. Start a wordpress instance (including a volume container): 

        docker create --name test-volumes --volume /var/lib/mysql --volume /var/www/html mwaeckerlin/scratch ""
        docker run -d --volumes-from test-volumes --name test-mysql -e MYSQL_ROOT_PASSWORD=$(pwgen -s 16 1) mysql
        docker run -d --volumes-from test-volumes --name test-wordpress --link test-mysql:mysql wordpress
  2. Start any number of other services ...
  3. Start a `reverse-proxy`

        docker run -d --restart=always --name reverse-proxy --link test-wordpress:test.mydomain.com -p 80:80 mwaeckerlin/reverse-proxy
  4. Head your browser to http://test.mydomain.com

Todo: Add SSL-Support with certificates
