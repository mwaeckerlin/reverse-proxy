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

# cleanup from previous run
rm -r /etc/nginx/sites-{available,enabled}/* || true

# setup an nginx configuration entry
declare -A conf
function configEntry() {
    local server=$1
    local cmd=$2
    conf[${server}]+="  $cmd
"
    echo "********** $server"
    echo "$cmd"
    echo "********************"
}

function writeConfigs() {
    local server
    for server in ${!conf[@]}; do
        echo "========== $server"
        local target=/etc/nginx/sites-available/${server}.conf
        ! test -e "${target}"
        if test -f /etc/ssl/${server}.crt -a -f /etc/ssl/${server}.key; then
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
  ssl_certificate /etc/ssl/${server}.crt;
  ssl_certificate_key /etc/ssl/${server}.key;
}
server {
  listen ${HTTPS_PORT};
  server_name ${server};
  ssl on;
  ssl_certificate /etc/ssl/${server}.crt;
  ssl_certificate_key /etc/ssl/${server}.key;
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
        cmd="rewrite ^/${frompath#*/}/(.*)$ http://${target}/\$1 redirect;"
    else
        cmd="return 301 \$scheme://${target}\$request_uri;"
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
    proxy_pass http://${target};
    subs_filter \"http://${target}\" \"http://${frompath}\";
    subs_filter \"${target}\" \"${frompath}\";
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
                  proxy_pass ${fromproxy};
                  subs_filter \"http://${fromip}:${fromport}\" \"http://${server}${fromlocation}\";
                  subs_filter \"http://${fromip}\" \"http://${server}${fromlocation}\";
                  subs_filter \"${fromip}:${fromport}\" \"${server}${fromlocation}\";
             subs_filter \"${fromip}\" \"${server}${fromlocation}\";
           }"
    configEntry "${server}" "${cmd}"
done

writeConfigs;

# run webserver
eval $proxycmd
