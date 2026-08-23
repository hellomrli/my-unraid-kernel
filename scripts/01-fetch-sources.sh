#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

need_cmd curl
need_cmd sha256sum

download_file "$KERNEL_ARCHIVE_URL" "$KERNEL_ARCHIVE"
verify_sha256 "$KERNEL_ARCHIVE" "$KERNEL_ARCHIVE_SHA256"

[ -n "$UNRAID_ZIP_URL" ] || die "UNRAID_ZIP_URL is required for full-package output"
download_file "$UNRAID_ZIP_URL" "$UNRAID_ZIP"
verify_sha256 "$UNRAID_ZIP" "$UNRAID_ZIP_SHA256"

download_file "$ZFS_TARBALL_URL" "$ZFS_TARBALL"
verify_sha256 "$ZFS_TARBALL" "$ZFS_TARBALL_SHA256"

log "Sources are ready"
