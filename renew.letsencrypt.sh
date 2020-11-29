#! /bin/sh -ex
if certbot renew -n --agree-tos -a webroot -w /acme --work-dir=/tmp --logs-dir=/tmp; then
    if pgrep nginx && nginx -t; then
        nginx -s reload
    fi
fi
