#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

need_cmd curl
need_cmd git
need_cmd sha256sum

download_file "$KERNEL_ARCHIVE_URL" "$KERNEL_ARCHIVE"
verify_sha256 "$KERNEL_ARCHIVE" "$KERNEL_ARCHIVE_SHA256"

if [ "$PLUGIN_ONLY" = "true" ]; then
  log "Plugin-only mode: skipping the official USB image and OpenZFS tarball"
else
  [ -n "$UNRAID_ZIP_URL" ] || die "UNRAID_ZIP_URL is required for full-package output"
  download_file "$UNRAID_ZIP_URL" "$UNRAID_ZIP"
  verify_sha256 "$UNRAID_ZIP" "$UNRAID_ZIP_SHA256"

  if [ "$USE_STOCK_ZFS" = "true" ]; then
    log "Using OpenZFS modules from the official Unraid package"
  else
    download_file "$ZFS_TARBALL_URL" "$ZFS_TARBALL"
    verify_sha256 "$ZFS_TARBALL" "$ZFS_TARBALL_SHA256"
  fi
fi

if [ -d "$I915_DIR/.git" ]; then
  log "Refreshing i915-sriov-dkms $I915_SRIOV_REF"
  git -C "$I915_DIR" fetch --depth 1 origin "refs/tags/$I915_SRIOV_REF"
  git -C "$I915_DIR" reset --hard FETCH_HEAD
  git -C "$I915_DIR" clean -ffdqx
else
  log "Cloning i915-sriov-dkms tag $I915_SRIOV_REF"
  git clone --depth 1 --branch "$I915_SRIOV_REF" "$I915_SRIOV_REPO" "$I915_DIR"
fi

if [ -n "$I915_SRIOV_COMMIT" ]; then
  actual_commit="$(git -C "$I915_DIR" rev-parse HEAD)"
  [ "$actual_commit" = "$I915_SRIOV_COMMIT" ] || die "i915 commit mismatch: expected $I915_SRIOV_COMMIT, got $actual_commit"
fi

log "Sources are ready"
