#!/bin/sh -e

sed -i '/^daemon off/d' /etc/nginx/nginx.conf
! test -e /etc/nginx/sites-enabled/default || rm /etc/nginx/sites-enabled/default

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

test -e /etc/letsencrypt/dhparam.pem || \
    openssl dhparam -out /etc/letsencrypt/dhparam.pem 4096

# run webserver
startNginx
if test -e /config/reverse-proxy.conf; then
    updateConfig $(cat /config/reverse-proxy.conf)
    /letsencrypt.start.sh
    while true; do
        inotifywait -q -e close_write /config/reverse-proxy.conf
        echo "**** configuration changed $(date)"
        updateConfig $(cat /config/reverse-proxy.conf)
    done
else
    updateConfig
    /letsencrypt.start.sh
    while true; do sleep 1000d; done
fi
