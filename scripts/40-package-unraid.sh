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

[ -s "$KERNEL_DIR/arch/x86/boot/bzImage" ] || die "Missing rebuilt bzImage"
[ -d "$MODULE_STAGE/lib/modules/$KERNEL_RELEASE" ] || die "Missing staged modules"
[ -s "$UNRAID_ZIP" ] || die "Missing official Unraid zip"

MODULE_DIR="$MODULE_STAGE/lib/modules/$KERNEL_RELEASE"
[ -s "$MODULE_DIR/extra/zfs.ko.xz" ] || die "Missing OpenZFS module"

PACKAGE_NAME="unRAIDServer-${UNRAID_VERSION}-Linux-${TARGET_KERNEL_VERSION}-x86_64"
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

log "Packaging rebuilt bzimage"
install -m 0644 "$KERNEL_DIR/arch/x86/boot/bzImage" "$OUT_DIR/bzimage-$KERNEL_RELEASE"
install -m 0644 "$KERNEL_DIR/arch/x86/boot/bzImage" "$OUT_DIR/bzimage"

log "Repacking bzroot with rebuilt $KERNEL_RELEASE modules"
python3 "$SCRIPT_DIR/unpack-bzroot.py" "$UNRAID_EXTRACT_DIR/bzroot" "$BZR_WORK"

# Replace the official module tree with the fully rebuilt one (in-tree modules
# plus OpenZFS), then link build/source as Unraid's tooling expects.
find "$BZR_WORK/lib/modules" -mindepth 1 -depth -type f -delete
find "$BZR_WORK/lib/modules" -mindepth 1 -depth -type l -delete
find "$BZR_WORK/lib/modules" -mindepth 1 -depth -type d -empty -delete
cp -a "$MODULE_DIR" "$BZR_WORK/lib/modules/$KERNEL_RELEASE"
ln -sfn "/usr/src/linux-$KERNEL_RELEASE" "$BZR_WORK/lib/modules/$KERNEL_RELEASE/build"
ln -sfn "/usr/src/linux-$KERNEL_RELEASE" "$BZR_WORK/lib/modules/$KERNEL_RELEASE/source"

(
  cd "$BZR_WORK"
  find ./kernel -print | LC_ALL=C sort | cpio --quiet -o -H newc --owner=0:0 > "$BZR_REPACK/early.cpio"
  find . -path './kernel' -prune -o -print | LC_ALL=C sort | cpio --quiet -o -H newc --owner=0:0 | zstd -19 -T0 -q -c > "$BZR_REPACK/main.cpio.zst"
)

cat "$BZR_REPACK/early.cpio" "$BZR_REPACK/main.cpio.zst" > "$OUT_DIR/bzroot-$KERNEL_RELEASE"
cp -f "$OUT_DIR/bzroot-$KERNEL_RELEASE" "$OUT_DIR/bzroot"

# Unraid's rc.S bzcheck verifies each boot file against a bare-hash .sha256
# sidecar; publish drop-in sidecars named exactly as they sit on the USB
# stick so users can copy them without recomputing anything.
sha256sum "$OUT_DIR/bzimage" | awk '{print $1}' > "$OUT_DIR/bzimage.sha256"
sha256sum "$OUT_DIR/bzroot" | awk '{print $1}' > "$OUT_DIR/bzroot.sha256"

# bzmodules is the /usr userspace image, not the kernel module tree. Preserve
# it byte-for-byte; the module tree above belongs in bzroot.
cp -f "$UNRAID_EXTRACT_DIR/bzmodules" "$OUT_DIR/bzmodules"

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
    "$(basename "$ZIP_OUT")" > "sha256sums-$KERNEL_RELEASE.txt"
)

log "Testing zip integrity"
unzip -tq "$ZIP_OUT"
log "Package: $ZIP_OUT"
log "Replace bzimage and bzroot together; bzmodules remains stock Unraid $UNRAID_VERSION."
