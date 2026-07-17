FROM mwaeckerlin/very-base AS build
WORKDIR /build
# Configuration lives in the template: the running container renders /etc/nginx
# from /etc/nginx.template with environment substitution at start (run-nginx),
# so our additions must land in the template too.
RUN mkdir -p /root/etc/nginx.template
RUN $PKG_INSTALL inotify-tools openssl g++
# openssl ships in the image so run-nginx can generate the DH parameters at
# start (not baked at build): high bits by default, generated once and kept on
# the persistent DHPARAM_FILE.
ENV EXE "/usr/bin/run-nginx /usr/bin/inotifywait /usr/bin/openssl"
COPY run-nginx.cpp /build
RUN g++ -std=c++17 -o /usr/bin/run-nginx run-nginx.cpp

# install binaries to /root
RUN tar cph $EXE \
    $(for f in $EXE; do \
    ldd $f | sed -n 's,.* => \([^ ]*\) .*,\1,p'; \
    done 2> /dev/null) 2> /dev/null \
    | tar xpC /root/

# Watch targets that must exist even when nothing is mounted over them:
# /config for the optional configuration file, letsencrypt/live for certificates.
RUN mkdir -p /root/config /root/etc/letsencrypt/live

RUN test -e /root/usr/bin/inotifywait
RUN test -e /root/usr/bin/run-nginx
RUN test -e /root/usr/bin/openssl

FROM mwaeckerlin/nginx AS assemble
COPY --from=build /root /
COPY --chown=root conf/ /etc/nginx.template/

FROM mwaeckerlin/scratch
ENV CONTAINERNAME "reverse-proxy"
EXPOSE 8080 8443
COPY --from=assemble / /
CMD [ "/usr/bin/run-nginx" ]
