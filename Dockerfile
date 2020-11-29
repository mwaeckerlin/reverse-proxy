FROM mwaeckerlin/letsencrypt as certbot

FROM mwaeckerlin/very-base AS tools
RUN $PKG_INSTALL inotify-tools openssl
RUN mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
RUN $ALLOW_USER /etc/nginx
RUN tar cp \
    $(find /usr/bin -type l) \
    $(which openssl) \
    $(which inotifywait) \
    $(for f in $(which openssl) $(which inotifywait); do \
    ldd $f | sed -n 's,.* => \([^ ]*\) .*,\1,p'; \
    done 2> /dev/null) 2> /dev/null \
    | tar xpC /root/
RUN tar cp \
    $(find /root -type l ! -exec test -e {} \; -exec echo -n "{} " \; -exec readlink {} \; | sed 's,/root\(.*\)/[^/]* \(.*\),\1/\2,') 2> /dev/null \
    | tar xpC /root/

FROM mwaeckerlin/nginx AS nginx
ADD proxy.conf /etc/nginx/proxy.conf
ADD default.conf /etc/nginx/conf.d/default.conf

FROM mwaeckerlin/scratch AS assemble
COPY --from=certbot / /
COPY --from=tools /root /
COPY --from=tools --chown=$RUN_USER /etc/nginx /etc/nginx 
COPY --from=nginx --chown=$RUN_USER /etc/nginx /etc/nginx
COPY --from=nginx /var/lib/nginx /var/lib/nginx
COPY --from=nginx --chown=$RUN_USER /var/lib/nginx/logs /var/lib/nginx/logs
COPY --from=nginx --chown=$RUN_USER /run/nginx /run/nginx
COPY --from=nginx /usr /usr
COPY --from=nginx /lib /lib
ADD start.sh /start.sh
ADD nginx-configure.sh /nginx-configure.sh
ADD letsencrypt.start.sh /letsencrypt.start.sh

FROM mwaeckerlin/scratch
ENV CONTAINERNAME "reverse-proxy"
ENV DEBUG_LEVEL "error"
ENV BASIC_AUTH_REALM ""
EXPOSE ${HTTP_PORT} ${HTTPS_PORT}
VOLUME /etc/nginx/sites-available
VOLUME /etc/nginx/sites-enabled
VOLUME /etc/nginx/basic-auth
VOLUME /etc/letsencrypt
VOLUME /acme
COPY --from=assemble / /