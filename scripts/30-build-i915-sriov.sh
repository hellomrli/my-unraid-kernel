#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

need_cmd make
need_cmd depmod
need_cmd git

[ -d "$KERNEL_DIR" ] || die "Missing prepared kernel tree. Run scripts/10-prepare-kernel.sh first."
[ -d "$I915_DIR" ] || die "Missing i915-sriov-dkms source. Run scripts/01-fetch-sources.sh first."
[ -d "$MODULE_STAGE/lib/modules" ] || die "Missing module staging area. Run scripts/20-build-kernel.sh first."

KREL="$(kernel_release)"
log "Building i915-sriov-dkms against $KREL"
log "Upstream driver branch $I915_SRIOV_BRANCH officially targets 6.17.x-7.0.x; 7.1.x may need fixes."

FORWARD_PORT_PATCH="$ROOT_DIR/patches/i915-sriov-dkms-linux-${TARGET_KERNEL_VERSION}-forward-port.patch"
if [ -s "$FORWARD_PORT_PATCH" ]; then
  if git -C "$I915_DIR" apply --check "$FORWARD_PORT_PATCH" >/dev/null 2>&1; then
    log "Applying i915 SR-IOV Linux $TARGET_KERNEL_VERSION forward-port patch"
    git -C "$I915_DIR" apply "$FORWARD_PORT_PATCH"
  elif git -C "$I915_DIR" apply --reverse --check "$FORWARD_PORT_PATCH" >/dev/null 2>&1; then
    log "i915 SR-IOV Linux $TARGET_KERNEL_VERSION forward-port patch already applied"
  else
    die "Cannot apply $FORWARD_PORT_PATCH cleanly"
  fi
fi

make -C "$KERNEL_DIR" M="$I915_DIR" -j"$JOBS" modules 2>&1 | tee "$LOG_DIR/build-i915-sriov.log"

log "Installing i915-sriov modules into updates/"
make -C "$KERNEL_DIR" M="$I915_DIR" INSTALL_MOD_PATH="$MODULE_STAGE" INSTALL_MOD_DIR=updates modules_install 2>&1 | tee "$LOG_DIR/install-i915-sriov.log"

depmod -b "$MODULE_STAGE" -F "$KERNEL_DIR/System.map" "$KREL"

find "$MODULE_STAGE/lib/modules/$KREL" -path '*/updates/*' -type f | sort > "$OUT_DIR/i915-sriov-installed-modules.txt"
log "Installed SR-IOV modules list: $OUT_DIR/i915-sriov-installed-modules.txt"
