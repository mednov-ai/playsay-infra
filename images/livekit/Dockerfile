# Temporary rebuild of the upstream stable release with its HTTP/2 fix.
FROM golang:1.27.3-alpine3.24@sha256:f2c872bcee949b7be9c490efd02b48a8a2fbf947cdf533f1c58525ec9d8170fd AS builder

ARG TARGETARCH=amd64
ENV GOTOOLCHAIN=local
ENV GOFLAGS=-p=2 GOMAXPROCS=2
WORKDIR /workspace

RUN apk add --no-cache patch \
    && wget -q -T 90 -O /tmp/livekit-source.tar.gz \
      https://codeload.github.com/livekit/livekit/tar.gz/385aa40f9292fe1db8caad87301e4b285b7c198a \
    && echo '3e55849d55ddb01df0407f0896d564d09e9b2b6697be1a827c9f4854e963dbff  /tmp/livekit-source.tar.gz' | sha256sum -c - \
    && tar -xzf /tmp/livekit-source.tar.gz --strip-components=1 -C /workspace \
    && rm /tmp/livekit-source.tar.gz

COPY livekit-dependency.patch /tmp/livekit-dependency.patch
RUN patch -p1 --dry-run < /tmp/livekit-dependency.patch \
    && patch -p1 < /tmp/livekit-dependency.patch \
    && go mod download \
    && go mod verify

RUN test -n "$TARGETARCH" \
    && mkdir -p /out/evidence \
    && CGO_ENABLED=0 GOOS=linux GOARCH="$TARGETARCH" go list -mod=readonly -deps ./cmd/server > /out/evidence/packages.txt \
    && if grep -Eq '^golang.org/x/crypto/openpgp($|/)' /out/evidence/packages.txt; then echo 'Unexpected openpgp runtime package' >&2; exit 1; fi \
    && CGO_ENABLED=0 GOOS=linux GOARCH="$TARGETARCH" go build -trimpath -buildvcs=false -mod=readonly -o /out/livekit-server ./cmd/server \
    && go version -m /out/livekit-server > /out/evidence/build-info.txt \
    && sha256sum /out/livekit-server > /out/evidence/binary.sha256 \
    && go tool nm /out/livekit-server > /tmp/livekit-symbols.txt \
    && if grep -q 'golang.org/x/crypto/openpgp' /tmp/livekit-symbols.txt; then echo 'Unexpected openpgp runtime symbols' >&2; exit 1; fi \
    && rm /tmp/livekit-symbols.txt

FROM alpine:3.24.3@sha256:c6b073f8e9e58d881f6ffba6ebf3b9ebd60b9e7d6e8337018c0e68bb5c356873
RUN apk upgrade --no-cache
COPY --from=builder /out/livekit-server /livekit-server
COPY --from=builder /out/evidence /usr/share/doc/livekit-build
ENTRYPOINT ["/livekit-server"]
