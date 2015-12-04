FROM ubuntu:latest
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
ENV HTTP_PORT 80
ENV HTTPS_PORT 443
VOLUME /etc/ssl/private
EXPOSE ${HTTP_PORT} ${HTTPS_PORT}
CMD /start.sh
