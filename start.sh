#!/bin/bash -ex

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
        echo "========== $server"
        local target=/etc/nginx/sites-available/${server}.conf
        ! test -e "${target}"
        if test "${LETSENCRYPT}" = "always" -o \( \( ! -f /etc/ssl/private/${server}.crt -o ! -f /etc/ssl/private/${server}.key; \) -a "${LETSENCRYPT}" = "missing" \); then
            mail=""
            if test -n "${MAILCONTACT}"; then
                if [[ "${MAILCONTACT}" =~ @ ]]; then
                    mail="-m ${MAILCONTACT}"
                else
                    mail="-m ${MAILCONTACT}@${server}"
                fi
            fi
            echo > /etc/cron.monthly/renew-certificates-${server//[^a-zA-Z0-0]/-} <<EOF
#! /bin/bash
/renew.sh ${LETSENCRYPT_OPTIONS} ${mail} -d ${server}
EOF
            chmod +x /etc/cron.monthly/renew-certificates-${server//[^a-zA-Z0-0]/-}
            /renew.sh ${LETSENCRYPT_OPTIONS} ${mail} -d ${server}
        fi
        if test -f /etc/ssl/private/${server}.crt -a -f /etc/ssl/private/${server}.key; then
            # write SSL configuration
            cat >> "${target}" <<EOF
server { # redirect http to https
  listen ${HTTP_PORT};
  server_name ${server};
  server_name www.${server};
  return 301 https://${server}\$request_uri;
}
server { # redirect www to non-www
  listen ${HTTPS_PORT};
  server_name www.${server};
  return 301 \$scheme://${server}\$request_uri;
  ssl on;
  ssl_certificate /etc/ssl/private/${server}.crt;
  ssl_certificate_key /etc/ssl/private/${server}.key;
}
server {
  listen ${HTTPS_PORT};
  server_name ${server};
  ssl on;
  ssl_certificate /etc/ssl/private/${server}.crt;
  ssl_certificate_key /etc/ssl/private/${server}.key;
${conf[${server}]}}
EOF
        else
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

# check for environment variables that are set for explicit redirecting
for redirect in $(env | sed -n 's/redirect-\(.*\)=.*/\1/p'); do
    frompath=$(echo "${redirect,,}" | sed 's/+/ /g;s/%\([0-9a-f][0-9a-f]\)/\\x\1/g;s/_/-/g' | xargs -0 printf "%b")
    server=${frompath%%/*}
    target=$(env | sed -n 's/redirect-'$redirect'=//p')
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
        fromlocation=/${frompath#*/}
    else
        fromlocation=
    fi     
    target=$(env | sed -n 's/forward-'$forward'=//p')
    cmd="location ${fromlocation}/ {
    include proxy.conf;
    proxy_pass http://${target}/;
    proxy_redirect http://${target}/ ${fromlocation}/;
    subs_filter \"http://${target}\" \"\$scheme://${frompath}\";
    subs_filter \"${target}\" \"${frompath}\";
    subs_filter \"http://localhost\" \"\$scheme://${frompath}\";
    subs_filter \"localhost\" \"${frompath}\";
  }"
    configEntry "${server}" "${cmd}"
done

# scan through all linked docker containers and add virtual hosts
for name in $(env | sed -n 's/_PORT_.*_TCP_ADDR=.*//p' | sort | uniq); do
    if env | egrep -q '^'${name}'_TO_PORT='; then
        fromport="$(env | sed -n 's/'${name}'_TO_PORT=//p')"
    else
        fromport="$(env | sed -n 's/'${name}'_PORT_.*_TCP_PORT=//p')"
    fi
    fromip="$(env | sed -n 's/'${name}'_PORT_'${fromport}'_TCP_ADDR=//p')"
    fromserverpath=$(echo "${name,,}" | sed 's/+/ /g;s/%\([0-9a-f][0-9a-f]\)/\\x\1/g;s/_/-/g' | xargs -0 printf "%b")
    server=${fromserverpath%%/*}
    if test "${fromserverpath#*/}" != "${fromserverpath}"; then
        fromlocation=/${fromserverpath#*/}
    else
        fromlocation=
    fi
    if test "${fromport}" = "${HTTP_PORT}"; then
        fromproxy="http://${fromip}"
    else
        fromproxy="http://${fromip}:${fromport}"
    fi
    cmd="location ${fromlocation}/ {
    include proxy.conf;
    #if ( \$host != '${server}' ) {
    #  rewrite ^/(.*)$ \$scheme://${server}${fromlocation}/\$1 permanent;
    #}
    proxy_cookie_domain ${fromip} ${server};
    proxy_cookie_path / ${fromlocation}/;
    proxy_pass ${fromproxy}/;
    proxy_redirect \$scheme://${server}${fromlocation} \$scheme://${server}${fromlocation};
    proxy_redirect \$scheme://${server} \$scheme://${server}${fromlocation};
    proxy_redirect /${fromlocation} \$scheme://${server}${fromlocation};
    proxy_redirect / \$scheme://${server}${fromlocation};
    proxy_redirect / /;
    subs_filter \"http://${fromip}:${fromport}\" \"\$scheme://${server}${fromlocation}\";
    subs_filter \"http://${fromip}\" \"\$scheme://${server}${fromlocation}\";
    subs_filter \"${fromip}:${fromport}\" \"${server}${fromlocation}\";
    subs_filter \"${fromip}\" \"${server}${fromlocation}\";"
    subs_filter \"http://localhost:${fromport}\" \"\$scheme://${server}${fromlocation}\";
    subs_filter \"http://localhost\" \"\$scheme://${server}${fromlocation}\";
    subs_filter \"localhost:${fromport}\" \"${server}${fromlocation}\";
    subs_filter \"localhost\" \"${server}${fromlocation}\";"
    if test -n "${fromlocation}"; then
        cmd+="
    subs_filter \"(src|href|action) *= *\\\"/\" \"\$1=\\\"${fromlocation}/\" ir;"
    fi
    cmd+="
  }"
    configEntry "${server}" "${cmd}"
done

writeConfigs;

# run crontab
if test "${LETSENCRYPT}" != "never"; then
    cron -L7
fi

# run webserver
eval $proxycmd
