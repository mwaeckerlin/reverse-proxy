FROM nginx:alpine

FROM mwaeckerlin/letsencrypt

ENV CONTAINERNAME "reverse-proxy"

COPY --from=0 /usr/lib/libssl.so.1.1 /usr/lib/libssl.so.1.1
COPY --from=0 /usr/lib/libcrypto.so.1.1 /usr/lib/libcrypto.so.1.1
COPY --from=0 /usr/lib/libpcre.so.1 /usr/lib/libpcre.so.1
COPY --from=0 /usr/sbin/nginx /usr/sbin/nginx
COPY --from=0 /usr/lib/nginx /usr/lib/nginx
COPY --from=0 /etc/nginx /etc/nginx

ADD proxy.conf /etc/nginx/proxy.conf
ADD ssl.conf /etc/nginx/conf.d/ssl.conf
ADD default.conf /etc/nginx/conf.d/default.conf
ADD nginx.conf /etc/nginx/nginx.conf
ADD error /etc/nginx/error
ADD nginx-configure.sh /nginx-configure.sh

ENV userdirs "/run/nginx /var/cache/nginx /etc/nginx/sites-enabled /etc/nginx/sites-available"
RUN apk add --no-cache --purge --clean-protected -u inotify-tools openssl \
    && mkdir -p ${userdirs} \
    && chown ${WWWUSER} -R ${userdirs} /etc/nginx/nginx.conf

USER ${WWWUSER}

# DEBUG_LEVEL is one of: debug, info, notice, warn, error, crit, alert, emerg
# logs are written to /var/log/nginx/error.log and /var/log/nginx/access.log
ENV DEBUG_LEVEL "error"
ENV LDAP_HOST ""
ENV LDAP_BASE_DN ""
ENV LDAP_BIND_DN ""
ENV LDAP_BIND_PASS ""
ENV LDAP_REALM "Restricted"
ENV BASIC_AUTH_REALM ""
EXPOSE ${HTTP_PORT} ${HTTPS_PORT}
VOLUME /etc/nginx/sites-available
VOLUME /etc/nginx/sites-enabled
VOLUME /etc/nginx/basic-auth
VOLUME /etc/nginx/client-ssl
