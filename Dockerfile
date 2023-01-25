FROM mwaeckerlin/very-base AS build
WORKDIR /build
RUN mkdir -p /root/etc/nginx
RUN $PKG_INSTALL inotify-tools openssl g++ nginx
ENV EXE "/usr/bin/run-nginx /usr/bin/inotifywait"
COPY run-nginx.cpp /build
RUN g++ -o /usr/bin/run-nginx run-nginx.cpp

# install binaries to /root
RUN tar cph $EXE \
    $(for f in $EXE; do \
    ldd $f | sed -n 's,.* => \([^ ]*\) .*,\1,p'; \
    done 2> /dev/null) 2> /dev/null \
    | tar xpC /root/

# make sure to change the following to at least 4096. 512 is just a dummy
# must be rebuilt before you release your configured image
ARG DHPARAM=512
RUN openssl dhparam -out /root/etc/nginx/dhparam.pem ${DHPARAM}

ARG FORWARD
ARG REDIRECT
ARG SSL
COPY nginx-configure.sh .
RUN ./nginx-configure.sh
RUN mv /etc/nginx/server.d /root/etc/nginx/

RUN test -e /root/usr/bin/inotifywait
RUN test -e /root/usr/bin/run-nginx

FROM mwaeckerlin/nginx AS assemble
COPY --from=build /root /
COPY --chown=root conf/ /etc/nginx/

FROM mwaeckerlin/very-base as test
RUN $PKG_INSTALL nginx
USER $RUN_USER
VOLUME /etc/letsencrypt/live
COPY --from=assemble / /
RUN /usr/sbin/nginx -t

FROM mwaeckerlin/scratch
ENV CONTAINERNAME "reverse-proxy"
EXPOSE 8080 8443
VOLUME /etc/letsencrypt/live
COPY --from=assemble / /
CMD [ "/usr/bin/run-nginx" ]
