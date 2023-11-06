FROM node:16.16.0-alpine3.16

LABEL org.opencontainers.image.source = "https://github.com/josedev-union/caprover-compose-action"

RUN apk add --no-cache git bash \
 && npm i -g caprover \
 && npm cache clean --force

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["sh","/entrypoint.sh"]
