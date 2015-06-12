#!/bin/bash -ex

OPT=${1:-"-f"}
PORT=80

# check how to run apache
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
        echo "  -n    don't start apache, only configure"
        exit;;
    (*) echo "unknown option $OPT, try --help"; exit 1;;
esac

# cleanup from previous run
rm -r /etc/nginx/sites-{available,enabled}/* || true

# scan through all linked docker containers and add virtual hosts
for name in $(env | sed -n 's/_PORT_.*_TCP_ADDR=.*//p'); do
    linkedhostname="$(env | sed -n 's/'${name}'_NAME=.*\///p')"
    linkedport="$(env | sed -n 's/'${name}'_PORT_.*_TCP_PORT=//p')"
    linkedip="$(env | sed -n 's/'${name}'_PORT_.*_TCP_ADDR=//p')"
    linkedserverpath=$(echo "${name,,}" | sed 's/+/ /g;s/%\([0-9a-f][0-9a-f]\)/\\x\1/g;s/_/-/g' | xargs -0 printf "%b")
    linkedservername=${linkedserverpath%%/*}
    if test "${linkedserverpath#*/}" -ne "${linkedserverpath}"; then
        linkedlocation=/${linkedserverpath#*/}
    else
        linkedlocation=
    fi
    if test "${linkedport}" = "${PORT}"; then
        linkedproxy="http://${linkedip}"
    else
        linkedproxy="http://${linkedip}:${linkedport}"
    fi
    site=${linkedhostname}_${linkedservername}_${linkedport}.conf
    cat > /etc/nginx/sites-available/${site} <<EOF
         server {
           listen ${PORT};
           server_name ${linkedservername};
           location ${linkedlocation}/ {
             include proxy.conf;
             proxy_pass ${linkedproxy};
             subs_filter "http://${linkedip}:${linkedport}" "http://${linkedservername}${linkedlocation}";
             subs_filter "http://${linkedip}" "http://${linkedservername}${linkedlocation}";
             subs_filter "${linkedip}:${linkedport}" "${linkedservername}${linkedlocation}";
             subs_filter "${linkedip}" "${linkedservername}${linkedlocation}";
           }
         }
EOF
    cat /etc/nginx/sites-available/${site}
    ln -s /etc/nginx/sites-available/${site} /etc/nginx/sites-enabled/${site}
done

# run apache
eval $proxycmd
