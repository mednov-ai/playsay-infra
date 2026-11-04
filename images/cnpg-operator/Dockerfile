# Pinned security rebuild of upstream CloudNativePG 1.30.1; scan the exact result before publication.
FROM golang:1.27.3-alpine3.24@sha256:f2c872bcee949b7be9c490efd02b48a8a2fbf947cdf533f1c58525ec9d8170fd AS builder
ENV GOTOOLCHAIN=local GOFLAGS=-p=2 GOMAXPROCS=2
WORKDIR /workspace

RUN wget -q -T 90 -O /tmp/cnpg-source.tar.gz \
      https://codeload.github.com/cloudnative-pg/cloudnative-pg/tar.gz/2a35abb4628f209d149825ef3c38011e0701ff2f \
    && echo 'c4ebb2fc69572825fb67bff43fbff32cb00791f4e3bbd1ae02835cb25fbc2be0  /tmp/cnpg-source.tar.gz' | sha256sum -c - \
    && tar -xzf /tmp/cnpg-source.tar.gz --strip-components=1 -C /workspace

# The reviewed patch pins every transitive module resolved during the security rebuild.
COPY cnpg-dependency.patch /tmp/cnpg-dependency.patch
RUN apk add --no-cache patch \
    && patch -p1 --dry-run < /tmp/cnpg-dependency.patch \
    && patch -p1 < /tmp/cnpg-dependency.patch \
    && go mod download \
    && go mod verify \
    && mkdir -p /out/evidence /out/operator \
    && cp go.mod go.sum /out/evidence/ \
    && go list -m all > /out/evidence/modules.txt

RUN set -eu; for arch in amd64 arm64; do \
      CGO_ENABLED=0 GOOS=linux GOARCH="$arch" go list -mod=readonly -deps ./cmd/manager > "/out/evidence/packages-$arch.txt"; \
      CGO_ENABLED=0 GOOS=linux GOARCH="$arch" go build -trimpath -buildvcs=false -mod=readonly \
        -ldflags '-s -w -X github.com/cloudnative-pg/cloudnative-pg/pkg/versions.buildVersion=1.30.1 -X github.com/cloudnative-pg/cloudnative-pg/pkg/versions.buildCommit=2a35abb -X github.com/cloudnative-pg/cloudnative-pg/pkg/versions.buildDate=2026-09-23' \
        -o "/out/operator/manager_$arch" ./cmd/manager; \
      go version -m "/out/operator/manager_$arch" > "/out/evidence/build-info-$arch.txt"; \
      sha256sum "/out/operator/manager_$arch" > "/out/evidence/binary-$arch.sha256"; \
    done \
    && ln -s operator/manager_amd64 /out/manager

FROM gcr.io/distroless/static-debian13:nonroot@sha256:25ac8f0c3b2334a9eb05452266bd4697864a8c8ef0ef71e5e6480d7f92868329
COPY --chown=65532:65532 --from=builder /out/operator/ /operator/
COPY --chown=65532:65532 --from=builder /out/manager /manager
COPY --chown=65532:65532 --from=builder /out/evidence/ /usr/share/doc/cnpg-build/
COPY --chown=65532:65532 --from=builder /workspace/licenses/ /licenses/
COPY --chown=65532:65532 --from=builder /workspace/LICENSE /licenses/LICENSE
USER 65532:65532
ENTRYPOINT ["/manager"]
