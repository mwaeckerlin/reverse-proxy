#!/bin/sh -ex

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
        exit 1
    fi
}

updateConfig() {
    /nginx-configure.sh $*
    if nginx -t; then
        nginx -s reload
        if test "${LETSENCRYPT}" != "off"; then
            if certbot renew -n --agree-tos -a webroot --webroot-path=/acme; then
                if nginx -t; then
                    nginx -s reload
                fi
            fi
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

if test "${LETSENCRYPT}" != "off"; then
    test -e /etc/letsencrypt/dhparam.pem ||
        openssl dhparam -out /etc/letsencrypt/dhparam.pem ${DHPARAM:-4096}
fi

# run webserver
startNginx
while true; do
    if test -e /config/reverse-proxy.conf; then
        updateConfig $(cat /config/reverse-proxy.conf)
    else
        updateConfig
    fi
    inotifywait -q -e close_write /config /etc/letsencrypt
    echo "**** configuration changed $(date)"
done
