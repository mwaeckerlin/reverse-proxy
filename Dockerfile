FROM mwaeckerlin/letsencrypt
MAINTAINER mwaeckerlin

ADD proxy.conf /etc/nginx/proxy.conf
ADD nginx-configure.sh /nginx-configure.sh
ADD start.sh /start.sh

RUN apt-get -y update
RUN apt-get -y install nginx nginx-extras inotify-tools
RUN sed -i 's/\(client_max_body_size\).*;/\1 0;/' /etc/nginx/proxy.conf

# DEBUG_LEVEL is one of: debug, info, notice, warn, error, crit, alert, emerg
# logs are written to /var/log/nginx/error.log and /var/log/nginx/access.log
ENV LOG_LEVEL ""
ENV LETSENCRYPT "missing"
ENV MAILCONTACT ""
ENV HTTP_PORT 80
ENV HTTPS_PORT 443
ENV LDAP_HOST ""
ENV LDAP_BASE_DN ""
ENV LDAP_BIND_DN ""
ENV LDAP_BIND_PASS ""
ENV LDAP_REALM "Restricted"
VOLUME /etc/ssl/private
EXPOSE ${HTTP_PORT} ${HTTPS_PORT}
ENTRYPOINT ["/start.sh"]
