#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

need_cmd make

[ -d "$KERNEL_DIR" ] || die "Missing prepared kernel tree. Run scripts/10-prepare-kernel.sh first."
[ -s "$KERNEL_DIR/.config" ] || die "Missing kernel configuration"
if [ "$REBUILD_KERNEL" != "true" ]; then
  [ -s "$KERNEL_DIR/arch/x86/boot/bzImage" ] || die "Missing prebuilt bzImage"
  [ -s "$KERNEL_DIR/Module.symvers" ] || die "Missing prebuilt Module.symvers"
fi
check_kernel_release

if [ "$REBUILD_KERNEL" = "true" ]; then
  if [ "$CLEAN_KERNEL_BUILD" = "true" ]; then
    log "Cleaning prebuilt kernel objects before the $CC rebuild"
    kmake clean
  fi

  log "Refreshing $KERNEL_RELEASE configuration for $CC"
  kmake olddefconfig
  cp "$KERNEL_DIR/.config" "$ROOT_DIR/config/generated-linux-${KERNEL_RELEASE}.config"

  log "Building $KERNEL_RELEASE bzImage and in-tree modules with $CC"
  kmake -j"$JOBS" bzImage modules 2>&1 | tee "$LOG_DIR/build-kernel.log"

  [ -s "$KERNEL_DIR/arch/x86/boot/bzImage" ] || die "Kernel build did not produce bzImage"
  [ -s "$KERNEL_DIR/Module.symvers" ] || die "Kernel build did not produce Module.symvers"
else
  log "Using ich777's prebuilt $KERNEL_RELEASE kernel and module ABI"
fi

log "Installing $KERNEL_RELEASE modules into staging"
if [ -d "$MODULE_STAGE" ]; then
  find "$MODULE_STAGE" -depth -type f -delete
  find "$MODULE_STAGE" -depth -type l -delete
  find "$MODULE_STAGE" -depth -type d -empty -delete
fi
mkdir -p "$MODULE_STAGE"

kmake INSTALL_MOD_PATH="$MODULE_STAGE" modules_install 2>&1 | tee "$LOG_DIR/install-kernel-modules.log"

printf '%s\n' "$KERNEL_RELEASE" > "$STATE_DIR/kernelrelease"
log "Staged kernel release: $KERNEL_RELEASE"
