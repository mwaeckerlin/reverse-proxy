FROM mwaeckerlin/letsencrypt
MAINTAINER mwaeckerlin

ADD proxy.conf /etc/nginx/proxy.conf
ADD start.sh /start.sh

RUN apt-get -y update
RUN apt-get -y install nginx nginx-extras
RUN sed -i 's/\(client_max_body_size\).*;/\1 0;/' /etc/nginx/proxy.conf
RUN ln -sf /dev/stdout /var/log/nginx/access.log
RUN ln -sf /dev/stderr /var/log/nginx/error.log

# DEBUG_LEVEL is one of: debug, info, notice, warn, error, crit, alert, emerg
# logs are written to /var/log/nginx/error.log and /var/log/nginx/access.log
ENV LOG_LEVEL ""
# possible parameters for LETSENCRYPT:
#  - always: always create SSL certificates from letsencrypt, overwrite existing
#  - missing: create SSL certificates from letsencrypt, if not already available
#  - never: disable letsencrypt
ENV LETSENCRYPT "always"
# mailcontact for letsencrypt, configure as one of these:
#  - user@host.url (all mails for all domains go to one account user@host.url)
#  - user (one account per SSL domain, mails go to account user@domain.url)
#  - <empty> (do not register an email address)
# defaults to admin@domain.url
ENV MAILCONTACT "admin"
ENV HTTP_PORT 80
ENV HTTPS_PORT 443
VOLUME /etc/ssl/private
EXPOSE ${HTTP_PORT} ${HTTPS_PORT}
CMD /start.sh
