#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

need_cmd make
need_cmd tar

[ -s "$KERNEL_ARCHIVE" ] || die "Missing $KERNEL_ARCHIVE. Run scripts/01-fetch-sources.sh first."

if [ -d "$KERNEL_DIR" ]; then
  if [ "$FORCE_PREPARE" = "true" ]; then
    log "Removing existing prepared kernel tree"
    find "$KERNEL_DIR" -depth -type f -delete
    find "$KERNEL_DIR" -depth -type l -delete
    find "$KERNEL_DIR" -depth -type d -empty -delete
  else
    check_kernel_release
    log "Using prepared kernel tree $KERNEL_DIR"
    exit 0
  fi
fi

log "Extracting ich777 $KERNEL_RELEASE kernel tree"
mkdir -p "$KERNEL_DIR"
tar -xf "$KERNEL_ARCHIVE" -C "$KERNEL_DIR"

[ -s "$KERNEL_DIR/.config" ] || die "Kernel archive did not contain .config"
[ -s "$KERNEL_DIR/Module.symvers" ] || die "Kernel archive did not contain Module.symvers"
[ -s "$KERNEL_DIR/arch/x86/boot/bzImage" ] || die "Kernel archive did not contain bzImage"
check_kernel_release

cp "$KERNEL_DIR/.config" "$ROOT_DIR/config/generated-linux-${KERNEL_RELEASE}.config"
log "Prepared prebuilt $KERNEL_RELEASE tree"
