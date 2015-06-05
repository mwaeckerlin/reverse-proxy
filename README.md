# Docker Image: Virtual Hosts Forward Proxy

On your computer start any number of services, then start a
`forwardproxy` and link to all your docker services. The link alias must
be the FQDN, the fully qualified domain name of your service.

Example:
  1. Start a wordpress instance (for simplicity without volume container): 

        docker run -d --name test-mysql -e MYSQL_ROOT_PASSWORD=$(pwgen -s 16 1) mysql
        docker run -d --name test-wordpress --link test-mysql:mysql wordpress
  2. Start any number of othe services ...
  3. Start a `forwardproxy`

        docker run -d --name forwardproxy --link test-wordpress:test.mydomain.com -p 80:80 forwardproxy
  4. Head your browser to http://test.mydomain.com


Todo: Add SSL-Support with certificates
