#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

need_cmd awk
need_cmd cpio
need_cmd depmod
need_cmd python3
need_cmd sha256sum
need_cmd unzip
need_cmd zip
need_cmd zstd

[ -s "$KERNEL_DIR/arch/x86/boot/bzImage" ] || die "Missing prebuilt bzImage"
[ -d "$MODULE_STAGE/lib/modules/$KERNEL_RELEASE" ] || die "Missing staged modules"
[ -s "$UNRAID_ZIP" ] || die "Missing official Unraid zip"

MODULE_DIR="$MODULE_STAGE/lib/modules/$KERNEL_RELEASE"
[ -s "$MODULE_DIR/kernel/drivers/gpu/drm/i915/i915.ko.xz" ] || die "Missing i915 SR-IOV module"
[ -s "$MODULE_DIR/updates/compat/intel_sriov_compat.ko.xz" ] || die "Missing i915 compatibility module"
if [ "$USE_STOCK_ZFS" != "true" ]; then
  [ -s "$MODULE_DIR/extra/zfs.ko.xz" ] || die "Missing OpenZFS module"
fi

I915_PACKAGE_VERSION="${I915_SRIOV_REF//./}"
I915_PACKAGE="i915-sriov-${I915_PACKAGE_VERSION}-${KERNEL_RELEASE}-${PACKAGE_BUILD}.txz"
[ -s "$OUT_DIR/$I915_PACKAGE" ] || die "Missing i915 plugin package"

PACKAGE_NAME="unRAIDServer-${UNRAID_VERSION}-Linux-${TARGET_KERNEL_VERSION}-i915-sriov-${I915_SRIOV_REF}-x86_64"
PACKAGE_DIR="$BUILD_DIR/$PACKAGE_NAME"
BZR_WORK="$BUILD_DIR/bzroot-work"
BZR_REPACK="$BUILD_DIR/bzroot-repack"
ZIP_OUT="$OUT_DIR/${PACKAGE_NAME}.zip"

log "Extracting official Unraid $UNRAID_VERSION package"
for dir in "$UNRAID_EXTRACT_DIR" "$PACKAGE_DIR" "$BZR_WORK" "$BZR_REPACK"; do
  if [ -d "$dir" ]; then
    find "$dir" -depth -type f -delete
    find "$dir" -depth -type l -delete
    find "$dir" -depth -type d -empty -delete
  fi
done
mkdir -p "$UNRAID_EXTRACT_DIR" "$BZR_WORK" "$BZR_REPACK"
unzip -q "$UNRAID_ZIP" -d "$UNRAID_EXTRACT_DIR"

[ -s "$UNRAID_EXTRACT_DIR/bzroot" ] || die "Official zip did not contain bzroot"
[ -s "$UNRAID_EXTRACT_DIR/bzmodules" ] || die "Official zip did not contain bzmodules"
[ -s "$UNRAID_EXTRACT_DIR/bzfirmware" ] || die "Official zip did not contain bzfirmware"

log "Packaging bzimage"
if [ "$USE_STOCK_BZIMAGE" = "true" ]; then
  install -m 0644 "$UNRAID_EXTRACT_DIR/bzimage" "$OUT_DIR/bzimage-$KERNEL_RELEASE"
  install -m 0644 "$UNRAID_EXTRACT_DIR/bzimage" "$OUT_DIR/bzimage"
else
  install -m 0644 "$KERNEL_DIR/arch/x86/boot/bzImage" "$OUT_DIR/bzimage-$KERNEL_RELEASE"
  install -m 0644 "$KERNEL_DIR/arch/x86/boot/bzImage" "$OUT_DIR/bzimage"
fi

log "Repacking bzroot with $KERNEL_RELEASE modules"
python3 "$SCRIPT_DIR/unpack-bzroot.py" "$UNRAID_EXTRACT_DIR/bzroot" "$BZR_WORK"
if [ "$MERGE_STOCK_MODULES" = "true" ]; then
  STOCK_MODULE_DIR="$BZR_WORK/lib/modules/$KERNEL_RELEASE"
  [ -d "$STOCK_MODULE_DIR" ] || die "Official bzroot does not contain $KERNEL_RELEASE modules"

  # Keep the beta's complete module tree (including its OpenZFS build) and
  # replace only the SR-IOV driver payload.
  for module in \
    updates/compat/intel_sriov_compat.ko.xz \
    kernel/drivers/gpu/drm/i915/i915.ko.xz \
    kernel/drivers/gpu/drm/i915/kvmgt.ko.xz \
    kernel/drivers/gpu/drm/xe/xe.ko.xz
  do
    [ -s "$MODULE_DIR/$module" ] || die "Missing staged module: $module"
    install -D -m 0644 "$MODULE_DIR/$module" "$STOCK_MODULE_DIR/$module"
  done
  depmod -b "$BZR_WORK" -F "$KERNEL_DIR/System.map" "$KERNEL_RELEASE"
else
  find "$BZR_WORK/lib/modules" -mindepth 1 -depth -type f -delete
  find "$BZR_WORK/lib/modules" -mindepth 1 -depth -type l -delete
  find "$BZR_WORK/lib/modules" -mindepth 1 -depth -type d -empty -delete
  cp -a "$MODULE_DIR" "$BZR_WORK/lib/modules/$KERNEL_RELEASE"
  ln -sfn "/usr/src/linux-$KERNEL_RELEASE" "$BZR_WORK/lib/modules/$KERNEL_RELEASE/build"
  ln -sfn "/usr/src/linux-$KERNEL_RELEASE" "$BZR_WORK/lib/modules/$KERNEL_RELEASE/source"
fi

(
  cd "$BZR_WORK"
  find ./kernel -print | LC_ALL=C sort | cpio --quiet -o -H newc --owner=0:0 > "$BZR_REPACK/early.cpio"
  find . -path './kernel' -prune -o -print | LC_ALL=C sort | cpio --quiet -o -H newc --owner=0:0 | zstd -19 -T0 -q -c > "$BZR_REPACK/main.cpio.zst"
)

cat "$BZR_REPACK/early.cpio" "$BZR_REPACK/main.cpio.zst" > "$OUT_DIR/bzroot-$KERNEL_RELEASE"
cp -f "$OUT_DIR/bzroot-$KERNEL_RELEASE" "$OUT_DIR/bzroot"

# bzmodules is the /usr userspace image, not the kernel module tree. Preserve
# it byte-for-byte; the module tree above belongs in bzroot.
cp -f "$UNRAID_EXTRACT_DIR/bzmodules" "$OUT_DIR/bzmodules"

cat > "$OUT_DIR/syslinux-append-i915-sriov.txt" <<EOF
intel_iommu=on i915.enable_guc=3 i915.max_vfs=${I915_MAX_VFS} module_blacklist=xe
EOF

log "Creating complete test USB zip"
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
  zip -qr -0 "$ZIP_OUT" .
)
(
  cd "$OUT_DIR"
  sha256sum "$(basename "$ZIP_OUT")" > "$(basename "$ZIP_OUT").sha256"
)

(
  cd "$OUT_DIR"
  sha256sum \
    "bzimage-$KERNEL_RELEASE" \
    "bzroot-$KERNEL_RELEASE" \
    bzmodules \
    "$I915_PACKAGE" \
    "$(basename "$ZIP_OUT")" > "sha256sums-$KERNEL_RELEASE.txt"
)

log "Testing zip integrity"
unzip -tq "$ZIP_OUT"
log "Package: $ZIP_OUT"
log "Replace bzimage and bzroot together; bzmodules remains stock Unraid $UNRAID_VERSION."
