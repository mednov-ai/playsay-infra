FROM alpine:3.20

RUN apk add --no-cache \
      age \
      aws-cli \
      bash \
      ca-certificates \
      chromium \
      curl \
      git \
      helm \
      jq \
      kubectl \
      minio-client \
      nodejs \
      openssl \
      postgresql17-client \
      yq \
  && ln -s /usr/bin/mcli /usr/local/bin/mc \
  && addgroup -S -g 65532 release-ops \
  && adduser -S -D -H -u 65532 -G release-ops release-ops

COPY backup.sh /usr/local/bin/playsay-release-backup

RUN chmod 0755 /usr/local/bin/playsay-release-backup

USER 65532:65532
WORKDIR /work
