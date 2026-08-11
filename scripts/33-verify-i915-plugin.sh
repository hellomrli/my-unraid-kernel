#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

need_cmd depmod
need_cmd awk
need_cmd md5sum
need_cmd modinfo
need_cmd paste
need_cmd readelf
need_cmd sha256sum
need_cmd tar
need_cmd xz

PACKAGE_VERSION="${I915_SRIOV_REF//./}"
PACKAGE_NAME="i915-sriov-${PACKAGE_VERSION}-${KERNEL_RELEASE}-${PACKAGE_BUILD}"
PACKAGE_OUT="$OUT_DIR/${PACKAGE_NAME}.txz"
VERIFY_DIR="$BUILD_DIR/verify-${PACKAGE_NAME}"
DEPMOD_REPORT="$OUT_DIR/depmod-plugin-${KERNEL_RELEASE}.txt"
VERIFY_REPORT="$OUT_DIR/verification-i915-${KERNEL_RELEASE}.txt"

[ -s "$PACKAGE_OUT" ] || die "Missing plugin package: $PACKAGE_OUT"
[ -s "$PACKAGE_OUT.md5" ] || die "Missing plugin MD5 file"
[ -d "$MODULE_STAGE/lib/modules/$KERNEL_RELEASE" ] || die "Missing module stage"
check_kernel_release

if [ -d "$VERIFY_DIR" ]; then
  find "$VERIFY_DIR" -depth -type f -delete
  find "$VERIFY_DIR" -depth -type l -delete
  find "$VERIFY_DIR" -depth -type d -empty -delete
fi
mkdir -p "$VERIFY_DIR"
tar -xJf "$PACKAGE_OUT" -C "$VERIFY_DIR"

COMPAT_MODULE="$VERIFY_DIR/lib/modules/$KERNEL_RELEASE/updates/compat/intel_sriov_compat.ko"
I915_COMPRESSED="$VERIFY_DIR/lib/modules/$KERNEL_RELEASE/kernel/drivers/gpu/drm/i915/i915.ko.xz"
I915_MODULE="$VERIFY_DIR/i915.ko"
[ -s "$COMPAT_MODULE" ] || die "Plugin is missing intel_sriov_compat.ko"
[ -s "$I915_COMPRESSED" ] || die "Plugin is missing i915.ko.xz"
xz -dc "$I915_COMPRESSED" > "$I915_MODULE"

verify_module() {
  local module="$1"
  local version vermagic compiler
  version="$(modinfo -F version "$module")"
  vermagic="$(modinfo -F vermagic "$module")"
  [ "$version" = "$I915_SRIOV_REF-sriov" ] || die "Wrong version for $module: $version"
  case "$vermagic" in
    "$KERNEL_RELEASE "*) ;;
    *) die "Wrong vermagic for $module: $vermagic" ;;
  esac

  if [ -n "$EXPECTED_CC_VERSION" ]; then
    compiler="$(readelf -p .comment "$module" 2>/dev/null | awk '/GCC: / { sub(/^.*GCC: /, "GCC: "); sub(/ *$/, ""); print }' | sort -u)"
    case "$compiler" in
      *" $EXPECTED_CC_VERSION"*) ;;
      *) die "Wrong compiler for $module: ${compiler:-missing .comment}" ;;
    esac
  fi
}

verify_xz_crc32() {
  local path="$1"
  local check
  check="$(xz --robot --list "$path" | awk -F '\t' '$1 == "totals" {print $7}')"
  [ "$check" = "CRC32" ] || die "Kernel module must use XZ CRC32: $path (got ${check:-unknown})"
}

verify_module "$COMPAT_MODULE"
verify_module "$I915_MODULE"
verify_xz_crc32 "$I915_COMPRESSED"

actual_md5="$(md5sum "$PACKAGE_OUT" | awk '{print $1}')"
expected_md5="$(awk 'NR == 1 {print $1}' "$PACKAGE_OUT.md5")"
[ "$actual_md5" = "$expected_md5" ] || die "Plugin MD5 mismatch"

depmod -e -b "$MODULE_STAGE" -F "$KERNEL_DIR/System.map" "$KERNEL_RELEASE" > "$DEPMOD_REPORT" 2>&1
[ ! -s "$DEPMOD_REPORT" ] || die "depmod reported unresolved symbols: $DEPMOD_REPORT"

resolved_i915="$(modinfo -b "$MODULE_STAGE" -k "$KERNEL_RELEASE" -n i915)"
case "$resolved_i915" in
  */kernel/drivers/gpu/drm/i915/i915.ko.xz) ;;
  *) die "depmod resolves i915 to an unexpected path: $resolved_i915" ;;
esac

{
  printf 'package=%s\n' "$(basename "$PACKAGE_OUT")"
  printf 'sha256=%s\n' "$(sha256sum "$PACKAGE_OUT" | awk '{print $1}')"
  printf 'md5=%s\n' "$actual_md5"
  printf 'version=%s\n' "$(modinfo -F version "$I915_MODULE")"
  printf 'vermagic=%s\n' "$(modinfo -F vermagic "$I915_MODULE")"
  printf 'compiler=%s\n' "$(readelf -p .comment "$I915_MODULE" 2>/dev/null | awk '/GCC: / { sub(/^.*GCC: /, "GCC: "); sub(/ *$/, ""); print }' | sort -u | paste -sd ';' -)"
  printf 'resolved_i915=%s\n' "$resolved_i915"
} > "$VERIFY_REPORT"

log "Plugin verification passed: $VERIFY_REPORT"
