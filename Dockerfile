FROM alpine:3.23

ARG BUILD_DATE

LABEL \
  maintainer="Logan Marchione <logan@loganmarchione.com>" \
  org.opencontainers.image.authors="Logan Marchione <logan@loganmarchione.com>" \
  org.opencontainers.image.title="docker-postfixrelay" \
  org.opencontainers.image.description="Runs Postfix (as a relay) in Docker" \
  org.opencontainers.image.created=$BUILD_DATE

RUN apk add --no-cache --update \
    bash \
    ca-certificates \
    cyrus-sasl-login \
    dumb-init \
    postfix \
    postfix-doc \
    tzdata

EXPOSE 25

VOLUME [ "/var/spool/postfix" ]

COPY ./entrypoint.sh /

COPY VERSION /

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/usr/bin/dumb-init", "--", "/entrypoint.sh"]

HEALTHCHECK CMD netstat -ltn | grep -c ":25" || exit 1
