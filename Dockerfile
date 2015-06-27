FROM ubuntu:latest
MAINTAINER mwaeckerlin

ADD proxy.conf /etc/nginx/proxy.conf
ADD start.sh /start.sh

RUN apt-get -y update
RUN apt-get -y install nginx nginx-extras

ENV HTTP_PORT 80
ENV HTTPS_PORT 443
VOLUME /etc/ssl
EXPOSE ${HTTP_PORT} ${HTTPS_PORT}
CMD /start.sh
