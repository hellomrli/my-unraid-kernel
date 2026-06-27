#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

need_cmd awk
need_cmd cpio
need_cmd sha256sum
need_cmd unmkinitramfs
need_cmd unzip
need_cmd zip
need_cmd zstd

[ -f "$KERNEL_DIR/arch/x86/boot/bzImage" ] || die "Missing built bzImage. Run scripts/20-build-kernel.sh first."
[ -d "$MODULE_STAGE/lib/modules" ] || die "Missing module staging area. Run scripts/20-build-kernel.sh first."
[ -f "$UNRAID_ZIP" ] || die "Missing official Unraid zip. Run scripts/01-fetch-sources.sh first."

KREL="$(kernel_release)"
MODULE_DIR="$MODULE_STAGE/lib/modules/$KREL"
[ -d "$MODULE_DIR" ] || die "Missing staged modules for $KREL"
[ -f "$MODULE_DIR/updates/drivers/gpu/drm/i915/i915.ko.xz" ] || die "Missing i915 SR-IOV module. Run scripts/30-build-i915-sriov.sh first."
[ -f "$MODULE_DIR/extra/zfs.ko.xz" ] || die "Missing ZFS module. Run scripts/35-build-zfs.sh first."

PACKAGE_NAME="unRAIDServer-${UNRAID_VERSION}-Linux-${TARGET_KERNEL_VERSION}-i915-sriov-x86_64"
PACKAGE_DIR="$BUILD_DIR/$PACKAGE_NAME"
BZR_WORK="$BUILD_DIR/bzroot-work"
BZR_REPACK="$BUILD_DIR/bzroot-repack"
ZIP_OUT="$OUT_DIR/${PACKAGE_NAME}.zip"

log "Extracting official Unraid $UNRAID_VERSION package"
rm -rf "$UNRAID_EXTRACT_DIR" "$PACKAGE_DIR" "$BZR_WORK" "$BZR_REPACK"
mkdir -p "$UNRAID_EXTRACT_DIR" "$BZR_WORK" "$BZR_REPACK"
unzip -q "$UNRAID_ZIP" -d "$UNRAID_EXTRACT_DIR"

[ -f "$UNRAID_EXTRACT_DIR/bzroot" ] || die "Official Unraid zip did not contain bzroot"
[ -f "$UNRAID_EXTRACT_DIR/bzmodules" ] || die "Official Unraid zip did not contain bzmodules"
[ -f "$UNRAID_EXTRACT_DIR/bzfirmware" ] || die "Official Unraid zip did not contain bzfirmware"

log "Packaging bzimage"
cp -f "$KERNEL_DIR/arch/x86/boot/bzImage" "$OUT_DIR/bzimage-$KREL"
cp -f "$KERNEL_DIR/arch/x86/boot/bzImage" "$OUT_DIR/bzimage"

log "Repacking bzroot with $KREL modules"
unmkinitramfs "$UNRAID_EXTRACT_DIR/bzroot" "$BZR_WORK"
rm -rf "$BZR_WORK/lib/modules"/*
cp -a "$MODULE_DIR" "$BZR_WORK/lib/modules/$KREL"
rm -f "$BZR_WORK/lib/modules/$KREL/build" "$BZR_WORK/lib/modules/$KREL/source"

(
  cd "$BZR_WORK"
  find ./kernel -print | LC_ALL=C sort | cpio --quiet -o -H newc --owner=0:0 > "$BZR_REPACK/early.cpio"
  find . -path './kernel' -prune -o -print | LC_ALL=C sort | cpio --quiet -o -H newc --owner=0:0 | zstd -19 -T0 -q -c > "$BZR_REPACK/main.cpio.zst"
)

cat "$BZR_REPACK/early.cpio" "$BZR_REPACK/main.cpio.zst" > "$OUT_DIR/bzroot-$KREL"
cp -f "$OUT_DIR/bzroot-$KREL" "$OUT_DIR/bzroot"

cat > "$OUT_DIR/syslinux-append-i915-sriov.txt" <<EOF
intel_iommu=on i915.enable_guc=3 i915.max_vfs=${I915_MAX_VFS} module_blacklist=xe
EOF

log "Creating full Unraid USB zip"
cp -a "$UNRAID_EXTRACT_DIR" "$PACKAGE_DIR"
cp -f "$OUT_DIR/bzimage" "$PACKAGE_DIR/bzimage"
cp -f "$OUT_DIR/bzroot" "$PACKAGE_DIR/bzroot"

(
  cd "$PACKAGE_DIR"
  sha256sum bzimage | awk '{print $1}' > bzimage.sha256
  sha256sum bzroot | awk '{print $1}' > bzroot.sha256
)

rm -f "$ZIP_OUT" "$ZIP_OUT.sha256"
(
  cd "$PACKAGE_DIR"
  zip -qr -9 "$ZIP_OUT" .
)
sha256sum "$ZIP_OUT" > "$ZIP_OUT.sha256"

(
  cd "$OUT_DIR"
  sha256sum "bzimage-$KREL" "bzroot-$KREL" "$(basename "$ZIP_OUT")" > "sha256sums-$KREL.txt"
)

log "Testing zip integrity"
unzip -tq "$ZIP_OUT"

log "Output:"
log "  $ZIP_OUT"
log "  $ZIP_OUT.sha256"
log "  $OUT_DIR/bzimage"
log "  $OUT_DIR/bzroot"
log "Use the full zip for Unraid USB replacement. Stock bzmodules and bzfirmware are preserved from Unraid $UNRAID_VERSION."
