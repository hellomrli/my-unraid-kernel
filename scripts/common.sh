#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BUILD_ENV_FILE="${BUILD_ENV_FILE:-$ROOT_DIR/config/build.env}"
if [ -f "$BUILD_ENV_FILE" ]; then
  # shellcheck disable=SC1091
  . "$BUILD_ENV_FILE"
fi

: "${UNRAID_VERSION:=7.3.2}"
: "${TARGET_KERNEL_VERSION:=6.18.43}"
: "${KERNEL_RELEASE:=${TARGET_KERNEL_VERSION}-Unraid}"
: "${JOBS:=all}"
: "${KERNEL_ARCHIVE_URL:=https://github.com/ich777/unraid_kernel/releases/download/${KERNEL_RELEASE}/linux-${KERNEL_RELEASE}.tar.xz}"
: "${KERNEL_ARCHIVE_SHA256:=}"
: "${UNRAID_ZIP_URL:=}"
: "${UNRAID_ZIP_SHA256:=}"
: "${I915_SRIOV_REPO:=https://github.com/strongtz/i915-sriov-dkms.git}"
: "${I915_SRIOV_REF:=2026.08.08}"
: "${I915_SRIOV_COMMIT:=}"
: "${I915_MAX_VFS:=7}"
: "${PACKAGE_BUILD:=1}"
: "${ZFS_VERSION:=2.4.3}"
: "${ZFS_TARBALL_URL:=https://github.com/openzfs/zfs/releases/download/zfs-${ZFS_VERSION}/zfs-${ZFS_VERSION}.tar.gz}"
: "${ZFS_TARBALL_SHA256:=}"
: "${FORCE_PREPARE:=false}"
: "${PLUGIN_ONLY:=false}"
: "${REBUILD_KERNEL:=true}"
: "${CLEAN_KERNEL_BUILD:=true}"
: "${CLEAN_ZFS_BUILD:=true}"
: "${EXPECTED_CC_VERSION:=}"
: "${CC:=gcc}"
: "${HOSTCC:=$CC}"
: "${CXX:=g++}"
: "${HOSTCXX:=$CXX}"
: "${HOSTCFLAGS:=}"
: "${HOSTLDFLAGS:=}"

# Export compiler selections so both kbuild and OpenZFS configure use the same
# toolchain. Callers can override these without changing the tracked config.
export CC HOSTCC CXX HOSTCXX HOSTCFLAGS HOSTLDFLAGS

if [ "$JOBS" = "all" ]; then
  JOBS="$(nproc --all)"
fi

DOWNLOAD_DIR="$ROOT_DIR/downloads"
BUILD_DIR="$ROOT_DIR/build"
LOG_DIR="$ROOT_DIR/logs"
OUT_DIR="$ROOT_DIR/out"
STATE_DIR="$BUILD_DIR/state"

KERNEL_ARCHIVE="$DOWNLOAD_DIR/linux-${KERNEL_RELEASE}.tar.xz"
UNRAID_ZIP="$DOWNLOAD_DIR/unRAIDServer-${UNRAID_VERSION}-x86_64.zip"
ZFS_TARBALL="$DOWNLOAD_DIR/zfs-${ZFS_VERSION}.tar.gz"
KERNEL_DIR="$BUILD_DIR/linux-${TARGET_KERNEL_VERSION}"
MODULE_STAGE="$BUILD_DIR/modules-stage"
I915_DIR="$BUILD_DIR/i915-sriov-dkms-${I915_SRIOV_REF}"
ZFS_DIR="$BUILD_DIR/zfs-${ZFS_VERSION}"
UNRAID_EXTRACT_DIR="$BUILD_DIR/unraid-${UNRAID_VERSION}-full"

mkdir -p "$DOWNLOAD_DIR" "$BUILD_DIR" "$LOG_DIR" "$OUT_DIR" "$STATE_DIR"

log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

kmake() {
  make -C "$KERNEL_DIR" \
    CC="$CC" \
    HOSTCC="$HOSTCC" \
    CXX="$CXX" \
    HOSTCXX="$HOSTCXX" \
    HOSTCFLAGS="$HOSTCFLAGS" \
    HOSTLDFLAGS="$HOSTLDFLAGS" \
    "$@"
}

download_file() {
  local url="$1"
  local out="$2"

  if [ -s "$out" ]; then
    log "Using existing $(basename "$out")"
    return
  fi

  log "Downloading $url"
  curl -L --fail --retry 3 --retry-delay 2 -o "$out.tmp" "$url"
  mv "$out.tmp" "$out"
}

verify_sha256() {
  local file="$1"
  local expected="$2"

  [ -n "$expected" ] || return 0
  [ -f "$file" ] || die "Cannot verify missing file: $file"

  local actual
  actual="$(sha256sum "$file" | awk '{print $1}')"
  [ "$actual" = "$expected" ] || die "SHA256 mismatch for $file: expected $expected, got $actual"
}

kernel_release() {
  kmake -s kernelrelease
}

check_kernel_release() {
  local actual
  actual="$(kernel_release)"
  [ "$actual" = "$KERNEL_RELEASE" ] || die "Kernel release mismatch: expected $KERNEL_RELEASE, got $actual"
}
