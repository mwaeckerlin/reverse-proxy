#!/bin/bash -e

OPT=${1:-"-f"}

# check how to run webserver
sed -i '/^daemon off/d' /etc/nginx/nginx.conf
proxycmd=nginx
case "${OPT}" in
    (-f) echo "daemon off;" >> /etc/nginx/nginx.conf;;
    (-d) ;;
    (-n) proxycmd="sleep infinity";;
    (-h|--help)
        echo "OPTIONS:"
        echo "  -h    show this help"
        echo "  -f    run in foreground"
        echo "  -d    run as daemon in background"
        echo "  -n    don't start webserver, only configure"
        exit;;
    (*) echo "unknown option $OPT, try --help"; exit 1;;
esac

# set log level
sed -e 's,\(error_log /var/log/nginx/error.log\).*;,\1 '"${DEBUG_LEVEL}"';,g' \
    -i /etc/nginx/nginx.conf

# cleanup from previous run
rm -r /etc/nginx/sites-{available,enabled}/* || true

# setup an nginx configuration entry
declare -A conf
function configEntry() {
    local server=$1
    local cmd=$2
    echo "********** $server"
    echo "$cmd"
    echo "********************"
    conf["${server}"]+="  $cmd
"
}

function writeConfigs() {
    local server
    for server in ${!conf[@]}; do
        local certfile="ssl_certificate /etc/ssl/private/${server}.crt"
        local keyfile="/etc/ssl/private/${server}.key"
        local havecerts=$(test -e "${certfile}" -a -e "${keyfile}" && echo 1 || echo 0)
        local getcerts=$(test "${LETSENCRYPT}" = "always" -o \( $havecerts -eq 0 -a "${LETSENCRYPT}" = "missing" \) && echo 1 || echo 0)
        echo "========== $server"
        local target=/etc/nginx/sites-available/${server}.conf
        ! test -e "${target}"
        if test $getcerts -eq 1; then
            local mail="--register-unsafely-without-email"
            certfile="/etc/letsencrypt/live/${server}/fullchain.pem"
            keyfile="/etc/letsencrypt/live/${server}/privkey.pem"
            echo "    - server ${server} get certificates from let's encrypt"
            if test -n "${MAILCONTACT}"; then
                if [[ "${MAILCONTACT}" =~ @ ]]; then
                    mail="-m ${MAILCONTACT}"
                else
                    mail="-m ${MAILCONTACT}@${server}"
                fi
            fi
            if ! test -e "${certfile}" -a -e "${keyfile}"; then
                certbot certonly -n --agree-tos -a standalone -d ${server} -d www.${server} ${mail}
            fi
            if ! test -e "${certfile}" -a -e "${keyfile}"; then
                echo "**** ERROR: Installation of Let's Encrypt certificates failed for $server" 1>&2
                exit 1
            fi
            havecerts=1
            cp /renew.letsencrypt.sh /etc/cron.monthly/renew
        fi
        if test $havecerts -eq 1; then
            echo "    - server ${server} supports SSL"
            # write SSL configuration
            cat >> "${target}" <<EOF
server { # redirect http to https
  listen ${HTTP_PORT};
  server_name ${server};
  server_name www.${server};
  location /.well-known {
      alias /acme/.well-known;
  }
  location / {
    return 301 https://${server}\$request_uri;
  }
}
server { # redirect www to non-www
  listen ${HTTPS_PORT};
  server_name www.${server};
  return 301 \$scheme://${server}\$request_uri;
  ssl on;
  ssl_certificate ${certfile};
  ssl_certificate_key ${keyfile};
}
server {
  listen ${HTTPS_PORT};
  server_name ${server};
  ssl on;
  ssl_certificate ${certfile};
  ssl_certificate_key ${keyfile};
${conf[${server}]}}
EOF
        else
            echo "    - no SSL support for server ${server}"
            cat > "${target}" <<EOF
server { # redirect www to non-www
  listen ${HTTP_PORT};
  server_name www.${server};
  return 301 \$scheme://${server}\$request_uri;
}
server {
  listen ${HTTP_PORT};
  server_name ${server};
${conf[${server}]}}
EOF
        fi
        cat "${target}"
        ln -s "${target}" /etc/nginx/sites-enabled/${server}.conf
        echo "===================="
    done
}

## forward address to another address in the form:
##   http(s)://fromurl/frombase → http://tourl:toport/tobase
## args:
##  $1: source in the form of fromurl/frombase
##  $2: target in the form of tourl:toport/tobase
##  $3: target ip address (optional)
function forward() {
    source=$1
    target=$2
    toip=$3
    frombase=
    fromurl=$source
    if [[ "${source}" =~ / ]]; then
        frombase=/${source#*/}
        frombase=${frombase%/}
        fromurl=${source%%/*}
    fi
    if [[ "${fromurl}" =~ : ]]; then
        fromurl=${fromurl%%:*}
    fi
    tobase=
    toport=
    tourl=$target
    if [[ "${target}" =~ / ]]; then
        tobase=/${target#*/}
        tobase=${tobase%/}
        tourl=${target%%/*}
    fi
    if [[ "${tourl}" =~ : ]]; then
        toport=:${tourl#*:}
        tourl=${tourl%%:*}
    fi
    if [ -z "$toip" ]; then
        toip=$(getent hosts ${tourl} | sed -n '1s, .*,,p')
    fi
    cmd="location ${frombase}/ {
    include proxy.conf;
    if (\$request_method ~ ^COPY\$) {
      rewrite $tobase/(.*) $frombase/\$1 break;
    }
    #if ( \$host != '${fromurl}' ) {
    #  rewrite ^/(.*)$ \$scheme://${fromurl}${frombase}/\$1 permanent;
    #}
    proxy_cookie_domain ${tourl} ${fromurl};
    proxy_cookie_path ${tobase}/ ${frombase}/;
    proxy_pass ${tourl}${toport}${tobase}/;
    proxy_redirect http://${tourl}${toport}${tobase}/ ${frombase}/;
    proxy_redirect http://${tourl}${toport}${tobase}/ \$scheme://${fromurl}${frombase}/;
    proxy_redirect ${tobase}/ \$scheme://${fromurl}${frombase}/;
    proxy_redirect ${tobase}/ ${frombase}/;
    proxy_redirect ${tobase}/ \$scheme://${fromurl}${frombase}/;
    subs_filter \"http://${tourl}${toport}${tobase}\" \"\$scheme://${fromurl}${frombase}\";
    subs_filter \"${tourl}${toport}${tobase}\" \"${fromurl}${frombase}\";
    subs_filter \"(src|href|action) *= *\\\"${tobase}\" \"\$1=\\\"${frombase}\" ir;
  }"
    configEntry "${fromurl}" "${cmd}"
}


################################################################################################
## Main ########################################################################################
################################################################################################

# check for environment variables that are set for explicit redirecting
for redirect in $(env | sed -n 's/redirect-\(.*\)=.*/\1/p'); do
    frompath=$(echo "${redirect,,}" | sed 's/+/ /g;s/%\([0-9a-f][0-9a-f]\)/\\x\1/g;s/_/-/g' | xargs -0 printf "%b")
    server=${frompath%%/*}
    target=$(env | sed -n 's/redirect-'${redirect//\//\\/}'=//p')
    if test "${frompath#*/}" != "${frompath}"; then
        cmd="rewrite ^/${frompath#*/}/(.*)$ \$scheme://${target}/\$1 redirect;"
    else
        cmd="rewrite ^/$ \$scheme://${target} redirect;"
    fi
    configEntry "${server}" "${cmd}"
done

# check for environment variables that are set for explicit forwarding
for forward in $(env | sed -n 's/forward-\(.*\)=.*/\1/p'); do
    source=$(echo "${forward,,}" | sed 's/+/ /g;s/%\([0-9a-f][0-9a-f]\)/\\x\1/g;s/_/-/g' | xargs -0 printf "%b")
    target=$(env | sed -n 's/forward-'${forward//\//\\/}'=//p')
    forward ${source} ${target}
done

# scan through all linked docker containers and add virtual hosts
for name in $(env | sed -n 's/_PORT_.*_TCP_ADDR=.*//p' | sort | uniq); do
    source=$(echo "${name,,}" | sed 's/+/ /g;s/%\([0-9a-f][0-9a-f]\)/\\x\1/g;s/_/-/g' | xargs -0 printf "%b")
    if env | egrep -q '^'${name}'_ENV_BASEPATH='; then
        tobase="$(env | sed -n 's/'${name//\//\\/}'_ENV_BASEPATH=//p')"
    else
        tobase=""
    fi
    if env | egrep -q '^'${name}'_TO_PORT='; then
        toport="$(env | sed -n 's/'${name//\//\\/}'_TO_PORT=//p')"
    else
        toport="$(env | sed -n 's/'${name//\//\\/}'_PORT_.*_TCP_PORT=//p' | head -1)"
    fi
    toip="$(env | sed -n 's/'${name//\//\\/}'_PORT_'${toport//\//\\/}'_TCP_ADDR=//p')"
    forward ${source} ${toip}:${toport}${tobase%/}
done

writeConfigs;

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
