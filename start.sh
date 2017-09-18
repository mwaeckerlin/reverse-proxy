#!/bin/bash -e

# define how to run webserver
sed -i '/^daemon off/d' /etc/nginx/nginx.conf

startNginx() {
    if nginx -t; then
        if pgrep nginx 2>&1 > /dev/null; then
            nginx -s reload
        else
            nginx
        fi
    else
        echo "**** ERROR: nginx configuration failed" 1>&2
    fi
}

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
startNginx
if test -e /reverse-proxy.conf; then
    updateConfig $(</reverse-proxy.conf)
    if test "${LETSENCRYPT}" != "never"; then
        if ! pgrep cron 2>&1 > /dev/null; then
            cron -L7
        fi
    fi
    while true; do
        inotifywait -q -e close_write /reverse-proxy.conf
        echo "**** configuration changed $(date)"
        updateConfig $(</reverse-proxy.conf)
    done
else
    updateConfig
    if test "${LETSENCRYPT}" != "never"; then
        if ! pgrep cron 2>&1 > /dev/null; then
            cron -L7
        fi
    fi
    sleep infinity
fi
