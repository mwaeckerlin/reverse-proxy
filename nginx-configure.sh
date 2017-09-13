#!/bin/bash -e

# setup nginx configuration from server list
declare -A conf

# internal use only
append_msg() {
    if test $# -ne 0; then
        echo -en ":\e[0m \e[1m$*"
    fi
    echo -e "\e[0m"
}

# write a notice
notice() {
    if test $# -eq 0; then
        return
    fi
    echo -e "\e[1m$*\e[0m" 1>&2
}

# write error message
error() {
    echo -en "\e[1;31merror" 1>&2
    append_msg $* 1>&2
}

# write a warning message
warning() {
    echo -en "\e[1;33mwarning" 1>&2
    append_msg $* 1>&2
}

# write a success message
success() {
    echo -en "\e[1;32msuccess" 1>&2
    append_msg $* 1>&2
}

# commandline parameter evaluation
nginx=$(pgrep nginx 2>&1 > /dev/null && echo running || echo off)
while test $# -gt 0; do
    case "$1" in
        (--help|-h) less <<EOF
SYNOPSIS

  $0 [OPTIONS]

OPTIONS

  --help, -h                 show this help
  --redirect, -r FROM TO     add a redirect
  --forward, -f FROM TO      add a forward rule

ENVIRONMENT

  Environment variables are evaluated and converted to redirect and
  forward requests, if they are defined in the following forman, and
  if they are url encoded:

  redirect-FROM=TO
  forward-FROM=TO

LINK

  Environment variables as set up by "docker create --link TO:FROM"
  are also evaluated. See README.md for more information on this
  topic.

FROM

  Externally visible domain name including optional base path, in the
  form "domain/base".

TO

  Internal target to forward external requests to, a host name or ip
  address, an optional port and an optional base path, in the form
  "host:port/base".

DESCRIPTION

Setup nginx reverse proxy configuration. Allow to redirect or forward
http and https requests. By default, ssl is enabled, certificates are
retrieved through letsencrypt and http is redirected to https. Also
all addresses will be accessible through the url or through www.url
which is redirected to url.

EXAMPLE

  $0 \\
     --redirect my.web-site.com  my.website.com \\
     --forward  my.website.com   server1.intranet:8001 \\
     --forward  another.site.com server2.intranet:8080 \\
     --forward  some.more.com    192.168.16.8

All external requests to my.web-site.com amd www.my.web-site.com are
redirected to my.website.com. All requests to my.website.com and
www.my.website.com are forwarded to the internal address
server1.intranet:8001. All requests to another.site.com and
www.another.site.com are forwarded to the internal address
server2.intranet:8080. All requests to another.site.com and
www.another.site.com are forwarded to the internal address
192.168.16.8:80. All http requests are redirected to https and
certificates are requested for the domains my.web-site.com,
my.website.com, another.site.com, some.more.com.

EOF
                    exit;;
        (--redirect|-r)
            if test $# -lt 3; then
                error "missing parameter at $*, try $0 --help"; exit 1
            fi
            redirect "$2" "$3"
            shift 2
            ;;
        (--forward|-f)
            if test $# -lt 3; then
                error "missing parameter at $*, try $0 --help"; exit 1
            fi
            forward "$2" "$3"
            shift 2
            ;;
        (*) error "unknow option $1, try $0 --help"; exit 1;;
    esac
    if test $# -eq 0; then
        error "missing parameter, try $0 --help"; exit 1
    fi
    shift;
done

# run a command, print the result and abort in case of error
# option: --no-check: ignore the result, continue in case of error
run() {
    check=1
    while test $# -gt 0; do
        case "$1" in
            (--no-check) check=0;;
            (*) break;;
        esac
        shift;
    done
    echo -en "\e[1m-> running:\e[0m $* ..."
    result=$($* 2>&1)
    res=$?
    if test $res -ne 0; then
        if test $check -eq 1; then
            error "failed with return code: $res"
            if test -n "$result"; then
                echo "$result"
            fi
            exit 1
        else
            warning "ignored return code: $res"
        fi
    else
        success
    fi
}

# error handler
function traperror() {
    set +x
    local err=($1) # error status
    local line="$2" # LINENO
    local linecallfunc="$3"
    local command="$4"
    local funcstack="$5"
    for e in ${err[@]}; do
        if test -n "$e" -a "$e" != "0"; then
            error "line $line - command '$command' exited with status: $e (${err[@]})"
            if [ "${funcstack}" != "main" -o "$linecallfunc" != "0" ]; then
                echo -n "   ... error at ${funcstack} "
                if [ "$linecallfunc" != "" ]; then
                    echo -n "called at line $linecallfunc"
                fi
                echo
            fi
            exit $e
        fi
    done
    success
    exit 0
}

# catch errors
trap 'traperror "$? ${PIPESTATUS[@]}" $LINENO $BASH_LINENO "$BASH_COMMAND" "${FUNCNAME[@]}" "${FUNCTION}"' ERR SIGINT INT TERM EXIT

##########################################################################################



# set log level
sed -e 's,\(error_log /var/log/nginx/error.log\).*;,\1 '"${DEBUG_LEVEL}"';,g' \
    -i /etc/nginx/nginx.conf

# cleanup from previous run
rm -r /etc/nginx/sites-{available,enabled}/* || true

# setup an nginx configuration entry
function configEntry() {
    local server=$1
    local cmd=$2
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
        if test $getcerts -eq 1 -o $havecerts -eq 1; then
            echo "    - server ${server} supports SSL"
            # write SSL configuration
            cat > "${target}" <<EOF
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
            if test "$nginx" = "running"; then
                if nginx -t; then
                    nginx -s reload
                    certbot certonly -n --agree-tos -a webroot --webroot-path=/acme -d ${server} -d www.${server} ${mail}
                    nginx -s reload
                else
                    echo "**** ERROR: Configuration failed when setting up $server" 1>&2
                fi
            else
                certbot certonly -n --agree-tos -a standalone -d ${server} -d www.${server} ${mail}
            fi
        fi
        if ! test -e "${certfile}" -a -e "${keyfile}"; then
            echo "**** ERROR: Installation of Let's Encrypt certificates failed for $server" 1>&2
            exit 1
        fi
        havecerts=1
        cp /renew.letsencrypt.sh /etc/cron.monthly/renew
    fi
}

## forward address to another address in the form:
##   http(s)://fromurl/frombase → http://tourl:toport/tobase
## args:
##  $1: source in the form of fromurl/frombase
##  $2: target in the form of tourl:toport/tobase
##  $3: target ip address (optional)
function forward() {
    local source=$1
    local target=$2
    local toip=$3
    local frombase=
    local fromurl=$source
    if [[ "${source}" =~ / ]]; then
        frombase=/${source#*/}
        frombase=${frombase%/}
        fromurl=${source%%/*}
    fi
    if [[ "${fromurl}" =~ : ]]; then
        fromurl=${fromurl%%:*}
    fi
    local tobase=
    local toport=
    local tourl=$target
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
    local cmd="location ${frombase}/ {
    include proxy.conf;
    if (\$request_method ~ ^COPY\$) {
      rewrite $tobase/(.*) $frombase/\$1 break;
    }
    #if ( \$host != '${fromurl}' ) {
    #  rewrite ^/(.*)$ \$scheme://${fromurl}${frombase}/\$1 permanent;
    #}
    proxy_cookie_domain ${tourl} ${fromurl};
    proxy_cookie_path ${tobase}/ ${frombase}/;
    proxy_pass http://${tourl}${toport}${tobase}/;
    proxy_redirect http://${tourl}${toport}${tobase}/ ${frombase}/;
    proxy_redirect http://${tourl}${toport}${tobase}/ \$scheme://${fromurl}${frombase}/;
    proxy_redirect ${tobase}/ \$scheme://${fromurl}${frombase}/;
    proxy_redirect ${tobase}/ ${frombase}/;
    proxy_redirect ${tobase}/ \$scheme://${fromurl}${frombase}/;
    subs_filter \"http://${tourl}${toport}${tobase}\" \"\$scheme://${fromurl}${frombase}\";
    subs_filter \"${tourl}${toport}${tobase}\" \"${fromurl}${frombase}\";"
    if [ "${tobase}" != "${frombase}" ]; then
        cmd+="
    subs_filter \"(src|href|action) *= *\\\"${tobase}\" \"\$1=\\\"${frombase}\" ir;"
    fi
    cmd+="
  }"
    configEntry "${fromurl}" "${cmd}"
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
    if test "${server}" != "${source}"; then
        cmd="rewrite ^/${source%/}/(.*)$ \$scheme://${target%/}/\$1 redirect;"
    else
        cmd="rewrite ^/$ \$scheme://${target%/}/ redirect;"
    fi
    configEntry "${server}" "${cmd}"
}

################################################################################################
## Main ########################################################################################
################################################################################################

# check for environment variables that are set for explicit redirecting
for redirect in $(env | sed -n 's/redirect-\(.*\)=.*/\1/p'); do
    frompath=$(echo "${redirect,,}" | sed 's/+/ /g;s/%\([0-9a-f][0-9a-f]\)/\\x\1/g;s/_/-/g' | xargs -0 printf "%b")
    target=$(env | sed -n 's/redirect-'${redirect//\//\\/}'=//p')
    redirect "$frompath" "$target"
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
