#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

need_cmd modinfo
need_cmd depmod
need_cmd readelf
need_cmd sha256sum
need_cmd strings
need_cmd tar
need_cmd unmkinitramfs
need_cmd unzip
need_cmd xz

PACKAGE_NAME="unRAIDServer-${UNRAID_VERSION}-Linux-${TARGET_KERNEL_VERSION}-i915-sriov-${I915_SRIOV_REF}-x86_64"
ZIP_OUT="$OUT_DIR/${PACKAGE_NAME}.zip"
VERIFY_DIR="$BUILD_DIR/verify-$KERNEL_RELEASE"
I915_PACKAGE_VERSION="${I915_SRIOV_REF//./}"
I915_PACKAGE="i915-sriov-${I915_PACKAGE_VERSION}-${KERNEL_RELEASE}-${PACKAGE_BUILD}.txz"
I915_PACKAGE_DIR="$BUILD_DIR/verify-$I915_PACKAGE_VERSION-$KERNEL_RELEASE"

[ -s "$ZIP_OUT" ] || die "Missing output zip: $ZIP_OUT"
[ -s "$OUT_DIR/bzroot-$KERNEL_RELEASE" ] || die "Missing custom bzroot"
[ -s "$OUT_DIR/bzimage-$KERNEL_RELEASE" ] || die "Missing custom bzimage"
[ -s "$OUT_DIR/$I915_PACKAGE" ] || die "Missing i915 plugin package"

if [ -d "$VERIFY_DIR" ]; then
  find "$VERIFY_DIR" -depth -type f -delete
  find "$VERIFY_DIR" -depth -type l -delete
  find "$VERIFY_DIR" -depth -type d -empty -delete
fi
mkdir -p "$VERIFY_DIR"
unmkinitramfs "$OUT_DIR/bzroot-$KERNEL_RELEASE" "$VERIFY_DIR"

MODULE_DIR="$VERIFY_DIR/lib/modules/$KERNEL_RELEASE"
[ -d "$MODULE_DIR" ] || die "Repacked bzroot does not contain $KERNEL_RELEASE"
[ ! -e "$VERIFY_DIR/lib/modules/6.18.38-Unraid" ] || die "Old 6.18.38 module tree remains in bzroot"

verify_module() {
  local path="$1"
  local expected_version="${2:-}"
  local vermagic
  vermagic="$(modinfo -F vermagic "$path")"
  case "$vermagic" in
    "$KERNEL_RELEASE "*) ;;
    *) die "Wrong vermagic for $path: $vermagic" ;;
  esac
  if [ -n "$expected_version" ]; then
    [ "$(modinfo -F version "$path")" = "$expected_version" ] || die "Wrong version for $path"
  fi
}

verify_xz_crc32() {
  local path="$1"
  local check
  check="$(xz --robot --list "$path" | awk -F '\t' '$1 == "totals" {print $7}')"
  [ "$check" = "CRC32" ] || die "Kernel module must use XZ CRC32: $path (got ${check:-unknown})"
}

module_compiler() {
  local path="$1"
  if [[ "$path" = *.xz ]]; then
    xz -dc "$path" | strings | awk '/GCC: / { sub(/^.*GCC: /, "GCC: "); print }' | sort -u
  else
    strings "$path" | awk '/GCC: / { sub(/^.*GCC: /, "GCC: "); print }' | sort -u
  fi
}

verify_module_compiler() {
  local path="$1"
  local compiler
  [ -n "$EXPECTED_CC_VERSION" ] || return 0
  compiler="$(module_compiler "$path")"
  case "$compiler" in
    *" $EXPECTED_CC_VERSION"*) ;;
    *) die "Wrong compiler for $path: ${compiler:-missing .comment}" ;;
  esac
}

I915_MODULE="$MODULE_DIR/kernel/drivers/gpu/drm/i915/i915.ko.xz"
COMPAT_MODULE="$MODULE_DIR/updates/compat/intel_sriov_compat.ko.xz"
KVMGT_MODULE="$MODULE_DIR/kernel/drivers/gpu/drm/i915/kvmgt.ko.xz"
XE_MODULE="$MODULE_DIR/kernel/drivers/gpu/drm/xe/xe.ko.xz"

verify_module "$COMPAT_MODULE" "$I915_SRIOV_REF-sriov"
verify_module "$I915_MODULE" "$I915_SRIOV_REF-sriov"
verify_module "$KVMGT_MODULE" "$I915_SRIOV_REF-sriov"
verify_module "$XE_MODULE" "$I915_SRIOV_REF-sriov"
verify_module "$MODULE_DIR/extra/spl.ko.xz" "$ZFS_VERSION-1"
verify_module "$MODULE_DIR/extra/zfs.ko.xz" "$ZFS_VERSION-1"

for module in \
  "$COMPAT_MODULE" \
  "$I915_MODULE" \
  "$KVMGT_MODULE" \
  "$XE_MODULE" \
  "$MODULE_DIR/extra/spl.ko.xz" \
  "$MODULE_DIR/extra/zfs.ko.xz"
do
  verify_xz_crc32 "$module"
done

for module in \
  "$COMPAT_MODULE" \
  "$I915_MODULE" \
  "$KVMGT_MODULE" \
  "$XE_MODULE"
do
  verify_module_compiler "$module"
done
if [ "$USE_STOCK_ZFS" != "true" ]; then
  verify_module_compiler "$MODULE_DIR/extra/spl.ko.xz"
  verify_module_compiler "$MODULE_DIR/extra/zfs.ko.xz"
fi

[ "$(find "$MODULE_DIR" -type f -name 'i915.ko*' | wc -l)" -eq 1 ] || die "Duplicate i915 modules in bzroot"
[ "$(find "$MODULE_DIR" -type f -name 'intel_sriov_compat.ko*' | wc -l)" -eq 1 ] || die "Duplicate compatibility modules in bzroot"

resolved_i915="$(modinfo -b "$VERIFY_DIR" -k "$KERNEL_RELEASE" -n i915)"
case "$resolved_i915" in
  */kernel/drivers/gpu/drm/i915/i915.ko.xz) ;;
  *) die "depmod does not prefer the SR-IOV i915 module: $resolved_i915" ;;
esac

if [ -d "$I915_PACKAGE_DIR" ]; then
  find "$I915_PACKAGE_DIR" -depth -type f -delete
  find "$I915_PACKAGE_DIR" -depth -type l -delete
  find "$I915_PACKAGE_DIR" -depth -type d -empty -delete
fi
mkdir -p "$I915_PACKAGE_DIR"
tar -xJf "$OUT_DIR/$I915_PACKAGE" -C "$I915_PACKAGE_DIR"
verify_module "$I915_PACKAGE_DIR/lib/modules/$KERNEL_RELEASE/updates/compat/intel_sriov_compat.ko" "$I915_SRIOV_REF-sriov"
verify_module "$I915_PACKAGE_DIR/lib/modules/$KERNEL_RELEASE/kernel/drivers/gpu/drm/i915/i915.ko.xz" "$I915_SRIOV_REF-sriov"
verify_module_compiler "$I915_PACKAGE_DIR/lib/modules/$KERNEL_RELEASE/updates/compat/intel_sriov_compat.ko"
verify_module_compiler "$I915_PACKAGE_DIR/lib/modules/$KERNEL_RELEASE/kernel/drivers/gpu/drm/i915/i915.ko.xz"
verify_xz_crc32 "$I915_PACKAGE_DIR/lib/modules/$KERNEL_RELEASE/kernel/drivers/gpu/drm/i915/i915.ko.xz"

DEPMOD_REPORT="$OUT_DIR/depmod-$KERNEL_RELEASE.txt"
depmod -e -b "$VERIFY_DIR" -F "$KERNEL_DIR/System.map" "$KERNEL_RELEASE" > "$DEPMOD_REPORT" 2>&1
[ ! -s "$DEPMOD_REPORT" ] || die "depmod reported unresolved symbols; see $DEPMOD_REPORT"

VMLINUX_VERIFY="$VERIFY_DIR/vmlinux.verify"
"$KERNEL_DIR/scripts/extract-vmlinux" "$OUT_DIR/bzimage-$KERNEL_RELEASE" > "$VMLINUX_VERIFY"
KERNEL_BANNER="$(strings "$VMLINUX_VERIFY" | awk '!found && /^Linux version / { print; found=1 }')"
find "$VMLINUX_VERIFY" -delete
[ -s "$KERNEL_DIR/vmlinux" ] || die "Missing unstripped kernel ELF: $KERNEL_DIR/vmlinux"
KERNEL_COMPILER="$(readelf -p .comment "$KERNEL_DIR/vmlinux" 2>/dev/null | awk '/GCC: / { sub(/^.*GCC: /, "GCC: "); sub(/ *$/, ""); print }' | sort -u)"
if [ -n "$EXPECTED_CC_VERSION" ] && [ "$USE_STOCK_BZIMAGE" != "true" ]; then
  case "$KERNEL_COMPILER" in
    *" $EXPECTED_CC_VERSION"*) ;;
    *) die "Wrong compiler in vmlinux: ${KERNEL_COMPILER:-missing .comment}" ;;
  esac
  case "$KERNEL_BANNER" in
    *" $EXPECTED_CC_VERSION"*) ;;
    *) die "Wrong compiler in bzImage banner: ${KERNEL_BANNER:-missing banner}" ;;
  esac
fi

[ "$(sha256sum "$OUT_DIR/bzmodules" | awk '{print $1}')" = "$(unzip -p "$UNRAID_ZIP" bzmodules | sha256sum | awk '{print $1}')" ] || die "bzmodules differs from official Unraid $UNRAID_VERSION"
if [ "$USE_STOCK_BZIMAGE" = "true" ]; then
  [ "$(sha256sum "$OUT_DIR/bzimage-$KERNEL_RELEASE" | awk '{print $1}')" = "$(unzip -p "$UNRAID_ZIP" bzimage | sha256sum | awk '{print $1}')" ] || die "bzimage differs from official Unraid $UNRAID_VERSION"
fi
unzip -tq "$ZIP_OUT"

{
  printf 'kernel_release=%s\n' "$KERNEL_RELEASE"
  printf 'kernel_banner=%s\n' "$KERNEL_BANNER"
  printf 'kernel_compiler=%s\n' "$KERNEL_COMPILER"
  printf 'bzimage_source=%s\n' "$([ "$USE_STOCK_BZIMAGE" = "true" ] && printf official || printf rebuilt)"
  printf 'modules_source=%s\n' "$([ "$MERGE_STOCK_MODULES" = "true" ] && printf merged || printf rebuilt)"
  printf 'i915_version=%s\n' "$(modinfo -F version "$I915_MODULE")"
  printf 'i915_origin_kernel=%s\n' "$(modinfo -F origin_kernel "$I915_MODULE")"
  printf 'i915_vermagic=%s\n' "$(modinfo -F vermagic "$I915_MODULE")"
  printf 'zfs_version=%s\n' "$(modinfo -F version "$MODULE_DIR/extra/zfs.ko.xz")"
  printf 'i915_compiler=%s\n' "$(module_compiler "$I915_MODULE" | paste -sd ';' -)"
  printf 'zfs_compiler=%s\n' "$(module_compiler "$MODULE_DIR/extra/zfs.ko.xz" | paste -sd ';' -)"
  printf 'resolved_i915=%s\n' "$resolved_i915"
  printf 'plugin_package=%s\n' "$I915_PACKAGE"
  printf 'module_count=%s\n' "$(find "$MODULE_DIR" -type f -name '*.ko*' | wc -l)"
} > "$OUT_DIR/verification-$KERNEL_RELEASE.txt"

log "Static verification passed; report: $OUT_DIR/verification-$KERNEL_RELEASE.txt"
