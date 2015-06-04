FROM ubuntu:latest
MAINTAINER mwaeckerlin

ADD proxy_html.conf /etc/apache2/conf-available/proxy_html.conf
ADD start.sh /start.sh

RUN apt-get -y update
RUN apt-get -y install apache2 libapache2-mod-proxy-html
RUN a2enmod proxy proxy_http proxy_html xml2enc
RUN a2enconf proxy_html

EXPOSE 80
CMD /start.sh
