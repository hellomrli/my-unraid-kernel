#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

need_cmd depmod
need_cmd git
need_cmd make
need_cmd xz

[ -d "$KERNEL_DIR" ] || die "Missing prepared kernel tree. Run scripts/10-prepare-kernel.sh first."
[ -d "$I915_DIR/.git" ] || die "Missing i915 source. Run scripts/01-fetch-sources.sh first."
[ -d "$MODULE_STAGE/lib/modules/$KERNEL_RELEASE" ] || die "Missing module stage. Run scripts/20-build-kernel.sh first."
check_kernel_release

PATCH="$ROOT_DIR/patches/strongtz-2026.08.08-unraid-6x-slab.patch"
[ -s "$PATCH" ] || die "Missing Unraid slab compatibility patch: $PATCH"

if git -C "$I915_DIR" apply --check "$PATCH" >/dev/null 2>&1; then
  log "Applying Unraid 6.x slab compatibility patch"
  git -C "$I915_DIR" apply "$PATCH"
elif git -C "$I915_DIR" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
  log "Unraid 6.x slab compatibility patch already applied"
else
  die "Cannot apply $PATCH cleanly"
fi

log "Cleaning prior i915 SR-IOV objects"
kmake M="$I915_DIR" clean

log "Building strongtz i915 SR-IOV $I915_SRIOV_REF for $KERNEL_RELEASE"
kmake M="$I915_DIR" -j"$JOBS" modules 2>&1 | tee "$LOG_DIR/build-i915-sriov.log"

MODULE_DIR="$MODULE_STAGE/lib/modules/$KERNEL_RELEASE"
COMPAT_DIR="$MODULE_DIR/updates/compat"
I915_MODULE_DIR="$MODULE_DIR/kernel/drivers/gpu/drm/i915"
XE_MODULE_DIR="$MODULE_DIR/kernel/drivers/gpu/drm/xe"

for module in \
  "$I915_DIR/compat/intel_sriov_compat.ko" \
  "$I915_DIR/drivers/gpu/drm/i915/i915.ko" \
  "$I915_DIR/drivers/gpu/drm/i915/kvmgt.ko" \
  "$I915_DIR/drivers/gpu/drm/xe/xe.ko"
do
  [ -s "$module" ] || die "Expected module was not built: $module"
done

# Match the layout used by giganode's Unraid plugin package. Replacing the
# in-tree paths avoids leaving two modules with the same name after the plugin
# installs its persistent package at boot.
install -d "$COMPAT_DIR" "$I915_MODULE_DIR" "$XE_MODULE_DIR"
install -m 0644 "$I915_DIR/compat/intel_sriov_compat.ko" "$COMPAT_DIR/intel_sriov_compat.ko"
install -m 0644 "$I915_DIR/drivers/gpu/drm/i915/i915.ko" "$I915_MODULE_DIR/i915.ko"
install -m 0644 "$I915_DIR/drivers/gpu/drm/i915/kvmgt.ko" "$I915_MODULE_DIR/kvmgt.ko"
install -m 0644 "$I915_DIR/drivers/gpu/drm/xe/xe.ko" "$XE_MODULE_DIR/xe.ko"

xz -T0 -9 -f \
  "$COMPAT_DIR/intel_sriov_compat.ko" \
  "$I915_MODULE_DIR/i915.ko" \
  "$I915_MODULE_DIR/kvmgt.ko" \
  "$XE_MODULE_DIR/xe.ko"
depmod -b "$MODULE_STAGE" -F "$KERNEL_DIR/System.map" "$KERNEL_RELEASE"

printf '%s\n' \
  "updates/compat/intel_sriov_compat.ko.xz" \
  "kernel/drivers/gpu/drm/i915/i915.ko.xz" \
  "kernel/drivers/gpu/drm/i915/kvmgt.ko.xz" \
  "kernel/drivers/gpu/drm/xe/xe.ko.xz" \
  > "$OUT_DIR/i915-sriov-installed-modules.txt"
log "Installed all four SR-IOV driver modules in plugin-compatible paths"
