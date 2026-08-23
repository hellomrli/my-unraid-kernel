#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

required=(
  bash
  bc
  bison
  cpio
  curl
  depmod
  flex
  git
  make
  python3
  readelf
  sha256sum
  strings
  tar
  unzip
  xz
  zip
  zstd
)

missing=0
for cmd in "${required[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'missing: %s\n' "$cmd" >&2
    missing=1
  fi
done

for compiler in "$CC" "$HOSTCC" "$CXX" "$HOSTCXX"; do
  if ! command -v "$compiler" >/dev/null 2>&1; then
    printf 'missing compiler: %s\n' "$compiler" >&2
    missing=1
  fi
done

if [ -n "${HOSTCFLAGS:-}" ]; then
  export HOSTCFLAGS
fi
if [ -n "${HOSTLDFLAGS:-}" ]; then
  export HOSTLDFLAGS
fi

if [ "$missing" -ne 0 ]; then
  cat >&2 <<'EOF'

Install the missing build tools before compiling. Ubuntu/Debian package names
usually include: build-essential bc bison flex libelf-dev libssl-dev xz-utils git curl
kmod unzip zip zstd python3 autoconf automake libtool uuid-dev
libblkid-dev libudev-dev libaio-dev libattr1-dev libzstd-dev libcurl4-openssl-dev

EOF
  exit 1
fi

log "Environment looks usable"
log "cc: $CC ($("$CC" -dumpfullversion -dumpversion))"
log "hostcc: $HOSTCC ($("$HOSTCC" -dumpfullversion -dumpversion))"
log "hostcxx: $HOSTCXX ($("$HOSTCXX" -dumpfullversion -dumpversion))"
if ! printf '#include <gelf.h>\n' | "$HOSTCC" $HOSTCFLAGS -x c -E - >/dev/null 2>&1; then
  die "gelf.h is unavailable; install libelf-dev or set HOSTCFLAGS"
fi
if [ -n "$EXPECTED_CC_VERSION" ]; then
  actual_cc_version="$("$CC" -dumpfullversion -dumpversion)"
  [ "$actual_cc_version" = "$EXPECTED_CC_VERSION" ] || die "Expected GCC $EXPECTED_CC_VERSION, got $actual_cc_version"
fi
log "jobs: $JOBS"
