#!/bin/bash -e

. /letsencrypt-config.sh

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
sed -e 's,\(error_log\).*;,\1 stderr '"${DEBUG_LEVEL:-error}"';,g' \
    -e 's,\(access_log\).*;,\1 /dev/stdout combined;,g' \
    -i /etc/nginx/nginx.conf

reloadNginx() {
    if pgrep nginx 2>&1 > /dev/null; then
        if nginx -t; then
            nginx -s reload
        else
            echo "**** ERROR: Configuration failed when setting up $server" 1>&2
        fi
    fi
}

# setup an nginx configuration entry
function configEntry() {
    local server=$1
    local cmd=$2
    conf["${server}"]+="  $cmd
"
}

function writeHTTP() {
    local target="$1"
    local server="$2"
    local config="$3"
    cat > "${target}" <<EOF
server { # redirect www to non-www
  listen ${HTTP_PORT};
  server_name www.${server};
  location /.well-known {
      alias /acme/.well-known;
  }
  location / {
    return 301 http://${server}:${HTTP_PORT}\$request_uri;
  }
}
server {
  listen ${HTTP_PORT};
  server_name ${server};
  location /.well-known {
      alias /acme/.well-known;
  }
${conf[${server}]}}
EOF
    test -e /etc/nginx/sites-enabled/${server}.conf || ln -s "${target}" /etc/nginx/sites-enabled/${server}.conf
    reloadNginx
}

function writeHTTPS() {
    local target="$1"
    local server="$2"
    local config="$3"
    if ! test -e "$(certfile $server)" -a -e "$(keyfile $server)"; then
        echo "**** ERROR: fallback to http, certificates not found for $server"
        writeHTTP $*
        return
    fi
    cat > "${target}" <<EOF
server { # redirect http to https
  listen ${HTTP_PORT};
  server_name ${server};
  server_name www.${server};
  location /.well-known {
      alias /acme/.well-known;
  }
  location / {
    return 301 https://${server}:${HTTPS_PORT}\$request_uri;
  }
}
server { # redirect www to non-www
  listen ${HTTPS_PORT};
  server_name www.${server};
  return 301 \$scheme://${server}:${HTTPS_PORT}\$request_uri;
  ssl on;
  ssl_certificate $(certfile $server);
  ssl_certificate_key $(keyfile $server);
}
server {
  listen ${HTTPS_PORT};
  server_name ${server};
  ssl on;
  ssl_certificate $(certfile $server);
  ssl_certificate_key $(keyfile $server);
${config}
EOF
    test -e /etc/nginx/sites-enabled/${server}.conf || ln -s "${target}" /etc/nginx/sites-enabled/${server}.conf
    reloadNginx
}

function writeConfigs() {
    local server
    local tst=/var/tmp/nginx
    echo "---- configured servers: ${!conf[@]}"
    test -d "$tst" || mkdir -p "$tst"
    for file in /etc/nginx/sites-{available,enabled}/*; do
        test -e "$file" || break
        server=${file##*/}
        server=${server%.conf}
        # remove server if no more configured
        test "${conf[$server]+isset}" || \
            ( rm -r "$file" && echo "---- configuration removed for server ${server}" )
    done
    test -d $tst || mkdir $tst
    for server in ${!conf[@]}; do
        local cmp="${tst}/${server}"
        echo "${conf[${server}]}}" > "${cmp}.current"
        if test -e "${cmp}.last" && diff -q "${cmp}.current" "${cmp}.last" && grep -q ssl_certificate /etc/nginx/sites-available/${server}.conf; then
            # configuration has not changed
            echo "---- not changed: $server"
            continue
        fi
        echo "========== $server"
        local target=/etc/nginx/sites-available/${server}.conf
        writeHTTP "${target}" "$server" "${conf[${server}]}}"
        if test "${LETSENCRYPT}" != "off"; then
            installcerts "$server"
            writeHTTPS "${target}" "$server" "${conf[${server}]}}"
        fi
        cat "${target}"
        echo "===================="
        mv "${cmp}.current" "${cmp}.last"
    done
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
    proxy_cookie_domain ${tourl} ${fromurl};"
    if [ ${tobase}/ != ${frombase}/ ]; then
        cmd+="
    proxy_cookie_path ${tobase}/ ${frombase}/;"
    fi
    cmd+="
    proxy_pass http://${tourl}${toport}${tobase}/;
    proxy_redirect http://${tourl}${toport}${tobase}/ \$scheme://${fromurl}${frombase};

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

# commandline parameter evaluation
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
