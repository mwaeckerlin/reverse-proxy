#!/bin/bash -e

# define how to run webserver
sed -i '/^daemon off/d' /etc/nginx/nginx.conf
proxycmd=nginx

updateConfig() {
    /nginx-configure.sh $*
    if nginx -t; then
        nginx -s reload
        if certbot renew -n --agree-tos -a webroot --webroot-path=/acme; then
            nginx -s reload
        fi
        echo "**** configuration updated $(date)"
    else
        echo "#### ERROR: configuration not updated $(date)" 1>&2
    fi
}

# source all configuration files named *.conf.sh
for f in /*.conf.sh /run/secrets/*.conf.sh; do
    if test -e "$f"; then
        . "$f"
    fi
done

#test -e /etc/ssl/certs/dhparam.pem || \
#    openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048

# fix logging
! test -e /var/log/nginx/access.log || rm /var/log/nginx/access.log
! test -e /var/log/nginx/error.log || rm /var/log/nginx/error.log
ln -sf /proc/self/fd/1 /var/log/nginx/access.log
ln -sf /proc/self/fd/2 /var/log/nginx/error.log

# run webserver
eval $proxycmd
if test -e /reverse-proxy.conf; then
    updateConfig $(</reverse-proxy.conf)
    if test "${LETSENCRYPT}" != "never"; then
        cron -L7
    fi
    while true; do
        inotifywait -q -e close_write /reverse-proxy.conf
        echo "**** configuration changed $(date)"
        updateConfig $(</reverse-proxy.conf)
    done
else
    updateConfig
    if test "${LETSENCRYPT}" != "never"; then
        cron -L7
    fi
    sleep infinity
fi
