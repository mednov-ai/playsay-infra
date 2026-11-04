#!/usr/bin/env sh
set -eu

for name in IMAGE_REPOSITORY GIT_COMMIT BUILD_LABEL WORKSPACE DEPLOY_TO_DEV DEPLOY_TO_PROD; do
  eval "value=\${$name:-}"
  if [ -z "$value" ]; then echo "Missing required environment variable: $name" >&2; exit 1; fi
done
case "$IMAGE_REPOSITORY" in
  ghcr.io/mednov-ai/playsay-livekit-server|ghcr.io/mednov-ai/playsay-livekit-security-fixture) ;;
  *) echo "This runtime-boundary rule is only for the reviewed LiveKit image." >&2; exit 1 ;;
esac
case "$BUILD_LABEL" in
  ''|*[!A-Za-z0-9_.-]*) echo "Invalid image build label." >&2; exit 1 ;;
esac
IMAGE_NAME="${IMAGE_REPOSITORY##*/}"
BUILD_DIR="$WORKSPACE/.image-build/$IMAGE_NAME/$BUILD_LABEL"
REPORT_DIR="$WORKSPACE/image-security/$IMAGE_NAME/$BUILD_LABEL"
IMAGE_TAR="$BUILD_DIR/image.tar"
GENERIC_SCANNER="${PLATFORM_CI_ROOT:-$WORKSPACE}/scripts/ci/scan-image.sh"
if [ ! -s "$IMAGE_TAR" ] || [ ! -x "$GENERIC_SCANNER" ]; then
  echo "Missing image archive or reviewed full scanner." >&2
  exit 1
fi
for file in full.json blocking.json database-metadata.json; do
  if [ -e "$REPORT_DIR/$file" ]; then
    echo "Refusing to reuse a previous scan report." >&2
    exit 1
  fi
done
archive_before="$(sha256sum "$IMAGE_TAR" | awk '{print $1}')"
set +e
"$GENERIC_SCANNER"
scan_result=$?
set -e
case "$scan_result" in
  0) exit 0 ;;
  42) ;;
  *) echo "Full scan failed; no runtime-boundary rule can be applied." >&2; exit 1 ;;
esac

# The generic scanner must have completed and produced a valid report with
# blocking findings. Scanner errors, missing metadata and EOL OS still fail.
for file in full.json blocking.json database-metadata.json scanner-version.txt; do
  if [ ! -s "$REPORT_DIR/$file" ]; then
    echo "Incomplete full scan; no runtime-boundary rule can be applied." >&2
    exit 1
  fi
done
set +e
trivy convert --config '' --ignorefile '' --severity UNKNOWN,HIGH,CRITICAL \
  --format json --exit-code 42 --output "$REPORT_DIR/unfiltered-blocking.json" "$REPORT_DIR/full.json"
raw_result=$?
set -e
if [ "$raw_result" -ne 42 ] || [ ! -s "$REPORT_DIR/unfiltered-blocking.json" ]; then
  echo "Could not establish a valid unfiltered blocking report." >&2
  exit 1
fi

case "$(uname -m)" in
  x86_64) crane_arch=x86_64; crane_sha=0ab7a1d6932a213aed964ce97666c3077fe691c8606413674a8b3e0b9ec4cda0 ;;
  aarch64|arm64) crane_arch=arm64; crane_sha=898c0cff975f898a33e8c4580bdafb0e7c02c7faa33374e946762f97c4ab7110 ;;
  *) echo "Unsupported CI architecture." >&2; exit 1 ;;
esac
wget -q -T 90 -O "$BUILD_DIR/boundary-crane.tar.gz" \
  "https://github.com/google/go-containerregistry/releases/download/v0.22.1/go-containerregistry_Linux_${crane_arch}.tar.gz"
printf '%s  %s\n' "$crane_sha" "$BUILD_DIR/boundary-crane.tar.gz" | sha256sum -c -
tar -xzf "$BUILD_DIR/boundary-crane.tar.gz" -C "$BUILD_DIR" crane

# Fail closed if the upstream advisory changes, including its affected package
# list. A changed advisory requires a fresh review and a new pinned checksum.
wget -q -T 90 -O "$REPORT_DIR/GO-2026-5932-advisory.json" https://vuln.go.dev/ID/GO-2026-5932.json
printf '%s  %s\n' bde8769150ec1368d9a8dbd61fbbde52296de692c57147e02e3ae295e1981f11 "$REPORT_DIR/GO-2026-5932-advisory.json" | sha256sum -c -

"$BUILD_DIR/crane" export - "$BUILD_DIR/livekit-rootfs.tar" < "$IMAGE_TAR"
tar -xOf "$BUILD_DIR/livekit-rootfs.tar" livekit-server > "$BUILD_DIR/inspected-livekit-server"
binary_sha="$(sha256sum "$BUILD_DIR/inspected-livekit-server" | awk '{print $1}')"
if [ "$binary_sha" != a247e0ecbdd4cbe9491a220a58610767372e7353d89b81c0bfc464ed9496fbf0 ]; then
  echo "LiveKit binary differs from the reviewed outside-runtime evidence." >&2
  exit 1
fi
tar -xOf "$BUILD_DIR/livekit-rootfs.tar" usr/share/doc/livekit-build/packages.txt > "$REPORT_DIR/verified-livekit-packages.txt"
tar -xOf "$BUILD_DIR/livekit-rootfs.tar" usr/share/doc/livekit-build/build-info.txt > "$REPORT_DIR/verified-livekit-build-info.txt"
if grep -Eq '^golang.org/x/crypto/openpgp($|/)' "$REPORT_DIR/verified-livekit-packages.txt"; then
  echo "The affected OpenPGP package is present." >&2
  exit 1
fi
if ! grep -Eq 'golang.org/x/crypto[[:space:]]+v0\.58\.0' "$REPORT_DIR/verified-livekit-build-info.txt"; then
  echo "Unexpected Go crypto module version." >&2
  exit 1
fi
strings "$BUILD_DIR/inspected-livekit-server" > "$BUILD_DIR/livekit-strings.txt"
if grep -q 'golang.org/x/crypto/openpgp' "$BUILD_DIR/livekit-strings.txt"; then
  echo "The affected OpenPGP package appears in the binary." >&2
  exit 1
fi

cat > "$REPORT_DIR/livekit-outside-runtime.yaml" <<'EOF'
vulnerabilities:
  - id: GO-2026-5932
    paths:
      - livekit-server
    purls:
      - pkg:golang/golang.org/x/crypto@v0.58.0
    statement: Exact reviewed binary excludes the affected OpenPGP packages and symbols.
EOF
trivy convert --config '' --ignorefile "$REPORT_DIR/livekit-outside-runtime.yaml" --show-suppressed \
  --severity UNKNOWN,HIGH,CRITICAL --format json --exit-code 1 \
  --output "$REPORT_DIR/classified-blocking.json" "$REPORT_DIR/full.json"
if [ ! -s "$REPORT_DIR/classified-blocking.json" ]; then
  echo "Missing classified security report." >&2
  exit 1
fi
archive_after="$(sha256sum "$IMAGE_TAR" | awk '{print $1}')"
if [ "$archive_before" != "$archive_after" ]; then
  echo "Image archive changed during security classification." >&2
  exit 1
fi
cp "$REPORT_DIR/blocking.json" "$REPORT_DIR/raw-blocking.json"
cp "$REPORT_DIR/classified-blocking.json" "$REPORT_DIR/blocking.json"
printf '%s\n' "$archive_before" > "$BUILD_DIR/scanned.sha256"
cp "$BUILD_DIR/scanned.sha256" "$REPORT_DIR/image-archive.sha256"
printf 'outside-server-runtime: GO-2026-5932, binary sha256:%s, advisory sha256:%s\n' \
  "$binary_sha" bde8769150ec1368d9a8dbd61fbbde52296de692c57147e02e3ae295e1981f11 > "$REPORT_DIR/livekit-runtime-boundary.txt"
echo "The exact reviewed OpenPGP finding is outside the LiveKit binary; no other blocking findings remain."
