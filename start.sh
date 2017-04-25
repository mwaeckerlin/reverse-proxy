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
    frompath=$(echo "${forward,,}" | sed 's/+/ /g;s/%\([0-9a-f][0-9a-f]\)/\\x\1/g;s/_/-/g' | xargs -0 printf "%b")
    server=${frompath%%/*}
    if test "${frompath#*/}" != "${frompath}"; then
        fromlocation=${frompath#*/}
    else
        fromlocation=
    fi
    target=$(env | sed -n 's/forward-'${forward//\//\\/}'=//p')
    if test "${target##*:}" != "${target}"; then
        host="${target%:*}"
    else
        host=
    fi
    cmd="location /${fromlocation%/}/ {
    include proxy.conf;
    proxy_pass http://${target%/}/;
    proxy_redirect http://${target%/}/ /${fromlocation%/}/;
    "
    if test -n "$host"; then
        cmd+="proxy_redirect http://${host%/}/ /${fromlocation%/}/;
    subs_filter \"http://${host}\" \"\$scheme://${frompath}\";
    subs_filter \"${host}\" \"${frompath}\";
    "
    fi
    cmd+="subs_filter \"http://${target}\" \"\$scheme://${frompath}\";
    subs_filter \"${target}\" \"${frompath}\";
    subs_filter \"http://localhost\" \"\$scheme://${frompath}\";
    subs_filter \"localhost\" \"${frompath}\";
  }"
    configEntry "${server}" "${cmd}"
done

# scan through all linked docker containers and add virtual hosts
for name in $(env | sed -n 's/_PORT_.*_TCP_ADDR=.*//p' | sort | uniq); do
    if env | egrep -q '^'${name}'_ENV_BASEPATH='; then
        frombase="$(env | sed -n 's/'${name//\//\\/}'_ENV_BASEPATH=//p')"
    else
        frombase=""
    fi
    if env | egrep -q '^'${name}'_TO_PORT='; then
        fromport="$(env | sed -n 's/'${name//\//\\/}'_TO_PORT=//p')"
    else
        fromport="$(env | sed -n 's/'${name//\//\\/}'_PORT_.*_TCP_PORT=//p' | head -1)"
    fi
    fromip="$(env | sed -n 's/'${name//\//\\/}'_PORT_'${fromport//\//\\/}'_TCP_ADDR=//p')"
    fromserverpath=$(echo "${name,,}" | sed 's/+/ /g;s/%\([0-9a-f][0-9a-f]\)/\\x\1/g;s/_/-/g' | xargs -0 printf "%b")
    server=${fromserverpath%%/*}
    if test "${fromserverpath#*/}" != "${fromserverpath}"; then
        fromlocation=${fromserverpath#*/}
    else
        fromlocation=
    fi
    if test "${fromport}" = "${HTTP_PORT}"; then
        fromproxy="http://${fromip}"
    else
        fromproxy="http://${fromip}:${fromport}"
    fi
    cmd="location /${fromlocation} {
    include proxy.conf;
    set \$fixed_destination \$http_destination;
    if ( \$http_destination ~* ^https(.*)\$ ) {
      set \$fixed_destination http\$1;
    }
    proxy_set_header Destination \$fixed_destination;
    if (\$request_method ~ ^COPY\$) {
      rewrite $frombase/(.*) $frombase/\$1 break;
    }
    #if ( \$host != '${server}' ) {
    #  rewrite ^/(.*)$ \$scheme://${server}/${fromlocation}/\$1 permanent;
    #}
    proxy_cookie_domain ${fromip} ${server};"
    if test -z "$frombase"; then
        cmd+="
    proxy_cookie_path / /${fromlocation};"
    fi
    cmd+="
    proxy_pass ${fromproxy}${frombase%/}/;
    proxy_redirect \$scheme://${server}/${fromlocation} \$scheme://${server}/${fromlocation};
    proxy_redirect \$scheme://${server} \$scheme://${server}/${fromlocation};
    proxy_redirect /${fromlocation} \$scheme://${server}/${fromlocation};
    proxy_redirect / \$scheme://${server}/${fromlocation};
    proxy_redirect / /;"
    if test -z "$frombase"; then
        cmd+="
    subs_filter \"http://${fromip}:${fromport}\" \"\$scheme://${server}/${fromlocation}\";
    subs_filter \"http://${fromip}\" \"\$scheme://${server}/${fromlocation}\";
    subs_filter \"${fromip}:${fromport}\" \"${server}/${fromlocation}\";
    subs_filter \"${fromip}\" \"${server}/${fromlocation}\";
    subs_filter \"http://localhost:${fromport}\" \"\$scheme://${server}/${fromlocation}\";
    subs_filter \"http://localhost\" \"\$scheme://${server}/${fromlocation}\";
    subs_filter \"localhost:${fromport}\" \"${server}/${fromlocation}\";
    subs_filter \"localhost\" \"${server}/${fromlocation}\";"
        if test -n "${fromlocation}"; then
            cmd+="
    subs_filter \"(src|href|action) *= *\\\"/\" \"\$1=\\\"/${fromlocation}/\" ir;"
        fi
    fi
    cmd+="
  }"
    configEntry "${server}" "${cmd}"
done

writeConfigs;

test -e /etc/ssl/certs/dhparam.pem || \
    openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048


# run crontab
if test "${LETSENCRYPT}" != "never"; then
    /renew.letsencrypt.sh
    cron -L7
fi

# fix logging
! test -e /var/log/nginx/access.log || rm /var/log/nginx/access.log
! test -e /var/log/nginx/error.log || rm /var/log/nginx/error.log
ln -sf /proc/self/fd/1 /var/log/nginx/access.log
ln -sf /proc/self/fd/2 /var/log/nginx/error.log

# run webserver
eval $proxycmd
