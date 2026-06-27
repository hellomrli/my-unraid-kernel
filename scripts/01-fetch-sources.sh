#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

need_cmd curl
need_cmd git
need_cmd tar

download_file "$KERNEL_TARBALL_URL" "$KERNEL_TARBALL"
download_file "$BASE_KERNEL_ARCHIVE_URL" "$BASE_KERNEL_ARCHIVE"

if [ -d "$I915_DIR/.git" ]; then
  log "Updating i915-sriov-dkms"
  git -C "$I915_DIR" fetch --depth 1 origin "$I915_SRIOV_BRANCH"
  git -C "$I915_DIR" checkout -B "$I915_SRIOV_BRANCH" FETCH_HEAD
else
  log "Cloning i915-sriov-dkms branch $I915_SRIOV_BRANCH"
  git clone --depth 1 --branch "$I915_SRIOV_BRANCH" "$I915_SRIOV_REPO" "$I915_DIR"
fi

log "Sources are ready"
