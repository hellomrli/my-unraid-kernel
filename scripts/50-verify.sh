#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

PACKAGE_NAME="unRAIDServer-${UNRAID_VERSION}-Linux-${TARGET_KERNEL_VERSION}-x86_64"
ZIP_OUT="$OUT_DIR/${PACKAGE_NAME}.zip"
VERIFY_DIR="$BUILD_DIR/verify-$KERNEL_RELEASE"
VERIFY_REPORT="$OUT_DIR/verification-$KERNEL_RELEASE.txt"
EXTENDED_REPORT="$OUT_DIR/verification-extended-$KERNEL_RELEASE.txt"

# Invalidate both reports from this stage before rerunning any checks.
rm -f "$VERIFY_REPORT" "$EXTENDED_REPORT"

need_cmd modinfo
need_cmd depmod
need_cmd cmp
need_cmd python3
need_cmd readelf
need_cmd sha256sum
need_cmd strings
need_cmd unzip
need_cmd xz
need_cmd git
need_cmd zstd

[ -s "$ZIP_OUT" ] || die "Missing output zip: $ZIP_OUT"
[ -s "$OUT_DIR/bzroot-$KERNEL_RELEASE" ] || die "Missing custom bzroot"
[ -s "$OUT_DIR/bzimage-$KERNEL_RELEASE" ] || die "Missing custom bzimage"
verify_sha256 "$UNRAID_ZIP" "$UNRAID_ZIP_SHA256"
cmp -s "$KERNEL_DIR/arch/x86/boot/bzImage" "$OUT_DIR/bzimage-$KERNEL_RELEASE" || \
  die "Packaged bzimage differs from the built kernel"

# Check each complete port, including the NVMe flags on existing PCI IDs.
# Regular prebuilt upstream releases may choose a different patch set.
if [ -n "${SEED_KERNEL_ARCHIVE_URL:-}" ]; then
  PORT_SERIES="$ROOT_DIR/patches/linux-${TARGET_KERNEL_VERSION}-hardware.series"
  [ -s "$PORT_SERIES" ] || die "Missing Unraid hardware patch series: $PORT_SERIES"
  while IFS= read -r patch_name; do
    [ -n "$patch_name" ] || continue
    git -C "$KERNEL_DIR" apply --reverse --check "$ROOT_DIR/patches/$patch_name" \
      >/dev/null 2>&1 || die "Unraid hardware port missing or changed: $patch_name"
  done < "$PORT_SERIES"
fi

if [ -d "$VERIFY_DIR" ]; then
  find "$VERIFY_DIR" -depth -type f -delete
  find "$VERIFY_DIR" -depth -type l -delete
  find "$VERIFY_DIR" -depth -type d -empty -delete
fi
mkdir -p "$VERIFY_DIR"
# Read the baseline from the verified official ZIP, not a possibly stale
# extraction directory left by a previous build.
OFFICIAL_BZROOT="$VERIFY_DIR/official.bzroot"
unzip -p "$UNRAID_ZIP" bzroot > "$OFFICIAL_BZROOT"
CPIO_VERIFICATION="$(python3 "$SCRIPT_DIR/repack-bzroot.py" --verify \
  "$OFFICIAL_BZROOT" "$OUT_DIR/bzroot-$KERNEL_RELEASE")"
log "$CPIO_VERIFICATION"
rm -f "$OFFICIAL_BZROOT"
python3 "$SCRIPT_DIR/unpack-bzroot.py" "$OUT_DIR/bzroot-$KERNEL_RELEASE" "$VERIFY_DIR"

MODULE_DIR="$VERIFY_DIR/lib/modules/$KERNEL_RELEASE"

module_compiler() {
  local path="$1"
  if [[ "$path" = *.xz ]]; then
    xz -dc "$path" | strings | awk '/GCC: / { sub(/^.*GCC: /, "GCC: "); print }' | sort -u
  else
    strings "$path" | awk '/GCC: / { sub(/^.*GCC: /, "GCC: "); print }' | sort -u
  fi
}

ZFS_MODULE="$MODULE_DIR/extra/zfs.ko.xz"

DEPMOD_REPORT="$OUT_DIR/depmod-$KERNEL_RELEASE.txt"
depmod -e -b "$VERIFY_DIR" -F "$KERNEL_DIR/System.map" "$KERNEL_RELEASE" > "$DEPMOD_REPORT" 2>&1
[ ! -s "$DEPMOD_REPORT" ] || die "depmod reported unresolved symbols; see $DEPMOD_REPORT"

VMLINUX_VERIFY="$VERIFY_DIR/vmlinux.verify"
"$KERNEL_DIR/scripts/extract-vmlinux" "$OUT_DIR/bzimage-$KERNEL_RELEASE" > "$VMLINUX_VERIFY"
KERNEL_BANNER="$(strings "$VMLINUX_VERIFY" | awk '!found && /^Linux version / { print; found=1 }')"
case "$KERNEL_BANNER" in
  "Linux version $KERNEL_RELEASE "*) ;;
  *) die "Wrong kernel release in bzimage: ${KERNEL_BANNER:-missing banner}" ;;
esac
if [ -n "${SEED_KERNEL_ARCHIVE_URL:-}" ]; then
  # Source checks alone can pass against an old, already packaged bzImage.
  grep -aq 'PCIe ACS overrides enabled' "$VMLINUX_VERIFY" || \
    die "PCIe ACS override missing from packaged bzImage; rebuild the kernel"
  if grep -q '^CONFIG_USB4=m$' "$KERNEL_DIR/.config"; then
    modinfo -F parm "$MODULE_DIR/kernel/drivers/thunderbolt/thunderbolt.ko.xz" | \
      grep -Fq 'host_reset:reset USB4 host router (default: false)' || \
      die "Thunderbolt host_reset default missing from packaged module"
  fi
fi
find "$VMLINUX_VERIFY" -delete
[ -s "$KERNEL_DIR/vmlinux" ] || die "Missing unstripped kernel ELF: $KERNEL_DIR/vmlinux"
KERNEL_COMPILER="$(readelf -p .comment "$KERNEL_DIR/vmlinux" 2>/dev/null | awk '/GCC: / { sub(/^.*GCC: /, "GCC: "); sub(/ *$/, ""); print }' | sort -u)"
if [ -n "$EXPECTED_CC_VERSION" ]; then
  case "$KERNEL_COMPILER" in
    *" $EXPECTED_CC_VERSION"*) ;;
    *) die "Wrong compiler in vmlinux: ${KERNEL_COMPILER:-missing .comment}" ;;
  esac
  case "$KERNEL_BANNER" in
    *" $EXPECTED_CC_VERSION"*) ;;
    *) die "Wrong compiler in bzImage banner: ${KERNEL_BANNER:-missing banner}" ;;
  esac
fi

# Verify every module's ELF metadata and compression, module inventory, all
# preserved ZIP entries, boot aliases, sidecars and both checksum manifests.
python3 "$SCRIPT_DIR/verify-artifacts.py" \
  --official-zip "$UNRAID_ZIP" --package "$ZIP_OUT" \
  --root "$VERIFY_DIR" --kernel-config "$KERNEL_DIR/.config" \
  --kernel-release "$KERNEL_RELEASE" --unraid-version "$UNRAID_VERSION" \
  --zfs-version "$ZFS_VERSION" --expected-gcc "$EXPECTED_CC_VERSION" \
  --report "$EXTENDED_REPORT"

{
  printf 'kernel_release=%s\n' "$KERNEL_RELEASE"
  printf 'kernel_banner=%s\n' "$KERNEL_BANNER"
  printf 'kernel_compiler=%s\n' "$KERNEL_COMPILER"
  printf 'zfs_version=%s\n' "$(modinfo -F version "$ZFS_MODULE")"
  printf 'zfs_compiler=%s\n' "$(module_compiler "$ZFS_MODULE" | paste -sd ';' -)"
  printf 'module_count=%s\n' "$(find "$MODULE_DIR" -type f -name '*.ko*' | wc -l)"
  printf 'initramfs_preservation=%s\n' "$CPIO_VERIFICATION"
  printf 'extended_report=%s\n' "$(basename "$EXTENDED_REPORT")"
} > "$VERIFY_REPORT"

log "Static verification passed; report: $VERIFY_REPORT"
