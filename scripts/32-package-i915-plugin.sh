#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

need_cmd md5sum
need_cmd sha256sum
need_cmd tar
need_cmd xz

[ -s "$I915_DIR/compat/intel_sriov_compat.ko" ] || die "Missing built compatibility module"
[ -s "$I915_DIR/drivers/gpu/drm/i915/i915.ko" ] || die "Missing built i915 module"

PACKAGE_VERSION="${I915_SRIOV_REF//./}"
PACKAGE_NAME="i915-sriov-${PACKAGE_VERSION}-${KERNEL_RELEASE}-1"
PACKAGE_ROOT="$BUILD_DIR/${PACKAGE_NAME}-package"
PACKAGE_OUT="$OUT_DIR/${PACKAGE_NAME}.txz"
COMPAT_PATH="lib/modules/$KERNEL_RELEASE/updates/compat"
I915_PATH="lib/modules/$KERNEL_RELEASE/kernel/drivers/gpu/drm/i915"

if [ -d "$PACKAGE_ROOT" ]; then
  find "$PACKAGE_ROOT" -depth -type f -delete
  find "$PACKAGE_ROOT" -depth -type l -delete
  find "$PACKAGE_ROOT" -depth -type d -empty -delete
fi
install -d \
  "$PACKAGE_ROOT/$COMPAT_PATH" \
  "$PACKAGE_ROOT/$I915_PATH" \
  "$PACKAGE_ROOT/install"

# Keep the same two-file payload and paths as giganode/unraid-i915-sriov.
install -m 0644 \
  "$I915_DIR/compat/intel_sriov_compat.ko" \
  "$PACKAGE_ROOT/$COMPAT_PATH/intel_sriov_compat.ko"
xz -T0 -9 -c \
  "$I915_DIR/drivers/gpu/drm/i915/i915.ko" \
  > "$PACKAGE_ROOT/$I915_PATH/i915.ko.xz"

cat > "$PACKAGE_ROOT/install/slack-desc" <<EOF
           |-----handy-ruler------------------------------------------------------|
i915-sriov: i915-sriov (Intel i915 SR-IOV driver)
i915-sriov:
i915-sriov: Source: https://github.com/strongtz/i915-sriov-dkms
i915-sriov: Source version: $I915_SRIOV_REF
i915-sriov:
i915-sriov: Custom i915 SR-IOV package for Unraid $KERNEL_RELEASE.
i915-sriov:
i915-sriov:
i915-sriov:
i915-sriov:
i915-sriov:
EOF

find "$PACKAGE_ROOT" -type d -exec chmod 0755 {} +
find "$PACKAGE_ROOT" -type f -exec chmod 0644 {} +

tar \
  --sort=name \
  --owner=0 \
  --group=0 \
  --numeric-owner \
  -C "$PACKAGE_ROOT" \
  -cJf "$PACKAGE_OUT" \
  .

md5sum "$PACKAGE_OUT" | awk '{print $1}' > "$PACKAGE_OUT.md5"
(
  cd "$OUT_DIR"
  sha256sum "$(basename "$PACKAGE_OUT")" > "$(basename "$PACKAGE_OUT").sha256"
)
log "Plugin package: $PACKAGE_OUT"
