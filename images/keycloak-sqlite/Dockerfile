# Exploratory image only: rebuild Red Hat's exact source RPM with FTS5 disabled.
FROM quay.io/keycloak/keycloak@sha256:3f3c5f8e03c614774b4bd9173b88391fefa4153bfc010d8012d59ad825377332 AS upstream

FROM registry.access.redhat.com/ubi9/ubi:9.8@sha256:8f989cc9270da6abec0144c22846ed1e6e92e462dc7768ce0981c4ac1d574733 AS builder
USER 0
RUN dnf -y install rpm-build gcc make ncurses-devel readline-devel glibc-devel autoconf tcl-devel unzip cpio binutils python3
COPY --from=upstream /usr/lib64/libsqlite3.so.0.8.6 /tmp/original-sqlite.so
COPY probe_sqlite.py /tmp/probe_sqlite.py
RUN set -eu; \
    curl -fsSL --max-time 120 -o /tmp/sqlite.src.rpm \
      https://cdn-ubi.redhat.com/content/public/ubi/dist/ubi9/9/x86_64/baseos/source/SRPMS/Packages/s/sqlite-3.34.1-11.el9_8.src.rpm; \
    echo '4efcc956008f0468362b41bdba79111c41027b682bcdea3ecca3744cf50ebfd7  /tmp/sqlite.src.rpm' | sha256sum -c -; \
    rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release; \
    rpm -Kv /tmp/sqlite.src.rpm; \
    rpm -ivh /tmp/sqlite.src.rpm; \
    test "$(grep -c -- '--enable-fts5' /root/rpmbuild/SPECS/sqlite.spec)" -eq 1; \
    sed -i 's/--enable-fts5/--disable-fts5/' /root/rpmbuild/SPECS/sqlite.spec; \
    sed -i 's/^Release: 11%{?dist}$/Release: 11.playfix1%{?dist}/' /root/rpmbuild/SPECS/sqlite.spec; \
    grep -q '^Release: 11.playfix1%{?dist}$' /root/rpmbuild/SPECS/sqlite.spec

# Run the source RPM's default test suite, preserving every distribution
# patch. No file produced by this exploratory build is published.
RUN rpmbuild -bb /root/rpmbuild/SPECS/sqlite.spec

RUN set -eu; \
    package="$(find /root/rpmbuild/RPMS -name 'sqlite-libs-3.34.1-11.playfix1*.x86_64.rpm' -print)"; \
    test -n "$package" && test "$(printf '%s\n' "$package" | wc -l)" -eq 1; \
    mkdir -p /out/root /out/evidence; \
    cd /out/root; rpm2cpio "$package" | cpio -id; \
    test -f usr/lib64/libsqlite3.so.0.8.6; \
    python3 /tmp/probe_sqlite.py /tmp/original-sqlite.so /out/root/usr/lib64/libsqlite3.so.0.8.6 > /out/evidence/sqlite-probe.json; \
    nm -D --defined-only /tmp/original-sqlite.so | awk '{print $NF}' | sort -u > /tmp/original-exports; \
    nm -D --defined-only /out/root/usr/lib64/libsqlite3.so.0.8.6 | awk '{print $NF}' | sort -u > /tmp/rebuilt-exports; \
    comm -23 /tmp/original-exports /tmp/rebuilt-exports > /out/evidence/missing-original-exports.txt; \
    test ! -s /out/evidence/missing-original-exports.txt; \
    sha256sum /tmp/original-sqlite.so /out/root/usr/lib64/libsqlite3.so.0.8.6 "$package" > /out/evidence/sha256.txt; \
    cp /root/rpmbuild/SPECS/sqlite.spec /out/evidence/sqlite.spec

FROM upstream
USER 0
COPY --from=builder /out/root/usr/lib64/libsqlite3.so.0.8.6 /usr/lib64/libsqlite3.so.0.8.6
COPY --from=builder /out/evidence/ /usr/share/doc/sqlite-fixture/
USER 1000
