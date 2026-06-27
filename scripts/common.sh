#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$ROOT_DIR/config/build.env" ]; then
  # shellcheck disable=SC1091
  . "$ROOT_DIR/config/build.env"
fi

: "${UNRAID_VERSION:=7.3.1}"
: "${UNRAID_BASE_KERNEL:=6.18.33-Unraid}"
: "${TARGET_KERNEL_VERSION:=7.1.1}"
: "${LOCALVERSION:=-Unraid}"
: "${JOBS:=all}"
: "${KERNEL_TARBALL_URL:=https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-${TARGET_KERNEL_VERSION}.tar.xz}"
: "${BASE_KERNEL_ARCHIVE_URL:=https://github.com/ich777/unraid_kernel/releases/download/${UNRAID_BASE_KERNEL}/linux-${UNRAID_BASE_KERNEL}.tar.xz}"
: "${THOR_REPO_DIR:=thor2002ro-unraid_kernel}"
: "${THOR_CONFIG_FILE:=unraid_7.1.4_conf_regen-7.1-vendor-gcc}"
: "${I915_SRIOV_REPO:=https://github.com/strongtz/i915-sriov-dkms.git}"
: "${I915_SRIOV_BRANCH:=kernel-v7.0}"
: "${I915_MAX_VFS:=7}"
: "${FORCE_PREPARE:=false}"

if [ "$JOBS" = "all" ]; then
  JOBS="$(nproc --all)"
fi

DOWNLOAD_DIR="$ROOT_DIR/downloads"
BUILD_DIR="$ROOT_DIR/build"
LOG_DIR="$ROOT_DIR/logs"
OUT_DIR="$ROOT_DIR/out"
STATE_DIR="$BUILD_DIR/state"

KERNEL_TARBALL="$DOWNLOAD_DIR/linux-${TARGET_KERNEL_VERSION}.tar.xz"
BASE_KERNEL_ARCHIVE="$DOWNLOAD_DIR/linux-${UNRAID_BASE_KERNEL}.tar.xz"
KERNEL_DIR="$BUILD_DIR/linux-${TARGET_KERNEL_VERSION}"
MODULE_STAGE="$BUILD_DIR/modules-stage"
BASE_CONFIG_PATH="$BUILD_DIR/unraid-${UNRAID_BASE_KERNEL}.config"
I915_DIR="$ROOT_DIR/i915-sriov-dkms"

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

kernel_release() {
  make -s -C "$KERNEL_DIR" kernelrelease
}
