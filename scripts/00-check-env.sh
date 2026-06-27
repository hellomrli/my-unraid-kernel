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
  gcc
  git
  make
  pkg-config
  sha256sum
  tar
  unmkinitramfs
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

if [ "$missing" -ne 0 ]; then
  cat >&2 <<'EOF'

Install the missing build tools before compiling.
Ubuntu/Debian package names usually include:
  build-essential bc bison flex libelf-dev libssl-dev dwarves xz-utils git curl kmod unzip zip zstd pkg-config initramfs-tools-core

EOF
  exit 1
fi

log "Environment looks usable"
log "gcc: $(gcc -dumpfullversion -dumpversion)"
log "jobs: $JOBS"
