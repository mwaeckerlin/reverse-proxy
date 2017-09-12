#!/bin/bash -e

# source all configuration files named *.conf.sh
for f in /*.conf.sh /run/secrets/*.conf.sh; do
    if test -e "$f"; then
        . "$f"
done

# check how to run webserver
sed -i '/^daemon off/d' /etc/nginx/nginx.conf
proxycmd=nginx
if ! test -e /reverse-proxy.conf; then
    echo "daemon off;" >> /etc/nginx/nginx.conf;;
fi

# set log level
sed -e 's,\(error_log /var/log/nginx/error.log\).*;,\1 '"${DEBUG_LEVEL}"';,g' \
    -i /etc/nginx/nginx.conf

if test -e /reverse-proxy.conf; then
    /nginx-configure.sh $(</reverse-proxy.conf)
else
    /nginx-configure.sh
fi

#test -e /etc/ssl/certs/dhparam.pem || \
#    openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048


# run crontab
if test "${LETSENCRYPT}" != "never"; then
    certbot renew -n --agree-tos -a standalone 
    cron -L7
fi

# fix logging
! test -e /var/log/nginx/access.log || rm /var/log/nginx/access.log
! test -e /var/log/nginx/error.log || rm /var/log/nginx/error.log
ln -sf /proc/self/fd/1 /var/log/nginx/access.log
ln -sf /proc/self/fd/2 /var/log/nginx/error.log

# run webserver
eval $proxycmd
if test -e /reverse-proxy.conf; then
    while true; do
        inotifywait -q -e close_write /reverse-proxy.conf
        echo "**** configuration changed $(date)"
        /nginx-configure.sh $(</reverse-proxy.conf)
        if nginx -t; then
            nginx -s reload
            if certbot renew -n --agree-tos -a webroot --webroot-path=/acme; then
                nginx -s reload
            fi
        fi
        echo "**** configuration updated $(date)"
    done
fi
