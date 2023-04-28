#!/bin/sh -e

# setup nginx configuration from server list
CONF=/conf
TARGET=/etc/nginx/server.d
mkdir -p ${CONF} ${TARGET}

#function clientssl() {
#    if test -e /etc/nginx/client-ssl/client-ca.crt; then
#        cat <<EOF
#
#  ssl_client_certificate  /etc/nginx/client-ssl/client-ca.crt;
#  ssl_verify_client on;
#EOF
#    fi
#}

function writeHTTP() {
    local target="$1"
    local server="$2"
    cat >"${target}" <<EOF
server { # redirect www to non-www
  listen 8080;
  server_name www.${server};
  location /.well-known {
      alias /acme/.well-known;
  }
  location / {
    resolver 127.0.0.11:53 valid=30s;
    return 302 http://${server}\$request_uri;
  }
}
server {
  listen 8080;
  server_name ${server};
  set \$port 8080;
  error_page 502 /502.html;
  error_page 504 /504.html;
  error_page 404 /404.html;
  location ~ ^/(502|504|404)\.html\$ {
    root /etc/nginx/error/\$lang;
  }
  location ~ ^/(502|504|404)\.jpg\$ {
    root /etc/nginx/error;
  }
$(cat "${CONF}/${server}")
  location /.well-known {
      alias /acme/.well-known;
  }
}
EOF
    nginx -t
}

function writeHTTPS() {
    local target="$1"
    local server="$2"
    cat >"${target}" <<EOF
server { # redirect http to https
  listen 8080;
  server_name ${server} www.${server};
  location /.well-known {
      alias /acme/.well-known;
  }
  location / {
    resolver 127.0.0.11:53 valid=30s;
    return 302 https://${server}\$request_uri;
  }
}
server {
  listen 8443 ssl http2;
  server_name ${server} www.${server};
  set \$port 8443;
  add_header Strict-Transport-Security max-age=15552000 always;
  ssl_certificate /etc/letsencrypt/live/\$server_name/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/\$server_name/privkey.pem;
  error_page 502 /502.html;
  error_page 504 /504.html;
  error_page 404 /404.html;$(clientssl)
  location ~ ^/(502|504|404)\.html\$ {
    root /etc/nginx/error/\$lang;
  }
  location ~ ^/(502|504|404)\.jpg\$ {
    root /etc/nginx/error;
  }
$(cat "${CONF}/${server}")
  location /.well-known {
      alias /acme/.well-known;
  }
}
EOF
    nginx -t
}

function writeConfigs() {
    local server
    for server in $(ls -1 ${CONF}); do
        local target=${TARGET}/${server}.conf
        echo "========== $server"
        writeHTTP "${target}" "$server"
        if test "$SSL" != "off"; then
            writeHTTPS "${target}" "$server"
        fi
        cat "${target}"
        echo "===================="
    done
}

## forward address to another address in the form:
##   http(s)://fromurl:fromport/frombase → http(s)://tourl:toport/tobase
## args:
##  $1: source in the form of fromurl:fromport/frombase
##  $2: target in the form of [toscheme]tourl:toport/tobase
##  $3: target ip address (optional)
function forward() {
    local source=$1
    local target=${2#http*://}
    local toip=$3
    local frombase=
    local fromurl=$source
    local toscheme="http://"
    local fromport=
    echo "---- forward: $*"
    if test "${2}" != "${2#http://}" -o "${2}" != "${2#https://}"; then
        toscheme=${2%%://*}://
    fi
    if test "${source}" != "${source%%/*}"; then
        frombase=/${source#*/}
        frombase=${frombase%/}
        fromurl=${source%%/*}
    fi
    if test "${fromurl}" != "${fromurl%%:*}"; then
        fromport=:${fromurl#*:}
        fromurl=${fromurl%%:*}
    fi
    if test -z "$fromport"; then
        fromport=:\$port
    fi
    local tobase=
    local toport=
    local tourl=$target
    if test "${target}" != "${target%%/*}"; then
        tobase=/${target#*/}
        tobase=${tobase%/}
        tourl=${target%%/*}
    fi
    if test "${tourl}" != "${tourl%%:*}"; then
        toport=:${tourl#*:}
        tourl=${tourl%%:*}
    fi
    if [ -z "$toip" ]; then
        toip=$(getent hosts ${tourl} | sed -n '1s, .*,,p')
    fi
    cat >>"${CONF}/${fromurl}" <<EOF
  location ${frombase}/ {
EOF
#    if test -e /etc/nginx/basic-auth/${fromurl}/${frombase}.htpasswd; then
#        cat >>"${CONF}/${fromurl}" <<EOF
#    auth_basic \"${BASIC_AUTH_REALM:-${fromurl}/${frombase}}\";
#    auth_basic_user_file /etc/nginx/basic-auth/${fromurl}/${frombase}.htpasswd;
#EOF
#    else
#        if test -e /etc/nginx/basic-auth/${fromurl}.htpasswd; then
#            cat >>"${CONF}/${fromurl}" <<EOF
#    auth_basic \"${BASIC_AUTH_REALM:-${fromurl}}\";
#    auth_basic_user_file /etc/nginx/basic-auth/${fromurl}.htpasswd;
#EOF
#        fi
#    fi
    cat >>"${CONF}/${fromurl}" <<EOF
    include proxy.conf;
    resolver 127.0.0.11:53 valid=30s;
    set \$tourl ${tourl};
    if (\$request_method ~ ^COPY\$) {
      rewrite $tobase/(.*) $frombase/\$1 break;
    }
    proxy_cookie_domain ${tourl} ${fromurl};
EOF
    if [ ${tobase}/ != ${frombase}/ ]; then
        cat >>"${CONF}/${fromurl}" <<EOF
    proxy_cookie_path ${tobase}/ ${frombase}/;
EOF
    fi
    cat >>"${CONF}/${fromurl}" <<EOF
    proxy_pass ${toscheme}\$tourl${toport}${tobase};
EOF
    if echo "${PROXY_REDIRECT_OFF}" | egrep -q '^\b'"${fromurl//./\\.}${frombase}"'\b'; then
        cat >>"${CONF}/${fromurl}" <<EOF
    proxy_redirect off;
EOF
    else
        cat >>"${CONF}/${fromurl}" <<EOF
    proxy_redirect ${toscheme}\$tourl${toport}${tobase}/ \$scheme://${fromurl}${fromport}${frombase}/;
EOF
    fi
    cat >>"${CONF}/${fromurl}" <<EOF
  }
EOF
}

## redirects address to another address in the form:
##   http(s)://fromurl/frombase → http://tourl:toport/tobase
## args:
##  $1: source in the form of fromurl/frombase
##  $2: target in the form of tourl:toport/tobase
function redirect() {
    local source=$1
    local target=$2
    local server=${source%%/*}
    echo "---- redirect: $*"
    if test "${server}" != "${source}"; then
        cat >>"${CONF}/${server}" <<EOF
  rewrite ^/${source#${server}/}(/.*)?$ \$scheme://${target%/}\$1 permanent;
EOF
    else
        cat >>"${CONF}/${server}" <<EOF
  rewrite ^/$ \$scheme://${target%/}/ permanent;
EOF
    fi
}

################################################################################################
## Main ########################################################################################
################################################################################################

OIFS="$IFS"
IFS='
'
for line in $REDIRECT; do
    IFS="$OIFS"
    redirect $line
done
IFS='
'
for line in $FORWARD; do
    IFS="$OIFS"
    forward $line
done
IFS="$OIFS"

writeConfigs
