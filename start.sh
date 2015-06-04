#!/bin/bash -ex

# cleanup from previous run
rm -r /etc/apache2/sites-{available,enabled}/* || true

# scan through all linked docker containers and add virtual hosts
for name in $(env | sed -n 's/_PORT_.*_TCP_ADDR=.*//p'); do
    linkedhostname="$(env | sed -n 's/'${name}'_NAME=.*\///p')"
    linkedport="$(env | sed -n 's/'${name}'_PORT_.*_TCP_PORT=//p')"
    linkedip="$(env | sed -n 's/'${name}'_PORT_.*_TCP_ADDR=//p')"
    linkedservername=${name,,}
    site=${linkedhostname}_${linkedservername}_${linkedport}.conf
    cat > /etc/apache2/sites-available/${site} <<EOF
         <VirtualHost *:80>
             ServerName ${linkedservername}
             <Location />
                 ProxyPass "http://${linkedip}:${linkedport}/" nocanon
                 ProxyPassReverse "http://${linkedip}:${linkedport}/"
                 ProxyPassReverse "http://${linkedip}/"
                 ProxyPassReverseCookieDomain "${linkedip}" "${linkedservername}"
                 ProxyHTMLURLMap "http://${linkedip}:${linkedport}/" "http://${linkedservername}/"
                 ProxyHTMLURLMap "http://${linkedip}:${linkedport}" "http://${linkedservername}"
                 ProxyHTMLURLMap "http://${linkedip}/" "http://${linkedservername}/"
                 ProxyHTMLURLMap "http://${linkedip}" "http://${linkedservername}"
                 ProxyHTMLURLMap "${linkedip}:${linkedport}/" "${linkedservername}/"
                 ProxyHTMLURLMap "${linkedip}:${linkedport}" "${linkedservername}"
                 ProxyHTMLURLMap "${linkedip}/" "${linkedservername}/"
                 ProxyHTMLURLMap "${linkedip}" "${linkedservername}"
             </Location>
         </VirtualHost>
EOF
    cat /etc/apache2/sites-available/${site}
    a2ensite ${site}
done

# run apache
apache2ctl -DFOREGROUND
