#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

need_cmd make

[ -d "$KERNEL_DIR" ] || die "Missing prepared kernel tree. Run scripts/10-prepare-kernel.sh first."

log "Building kernel and modules"
make -C "$KERNEL_DIR" -j"$JOBS" bzImage modules 2>&1 | tee "$LOG_DIR/build-kernel.log"

log "Installing modules into staging area"
rm -rf "$MODULE_STAGE"
make -C "$KERNEL_DIR" INSTALL_MOD_PATH="$MODULE_STAGE" modules_install 2>&1 | tee "$LOG_DIR/install-kernel-modules.log"

KREL="$(kernel_release)"
printf '%s\n' "$KREL" > "$STATE_DIR/kernelrelease"
log "Kernel release: $KREL"
