#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

need_cmd modinfo
need_cmd depmod
need_cmd python3
need_cmd readelf
need_cmd sha256sum
need_cmd strings
need_cmd unzip
need_cmd xz

PACKAGE_NAME="unRAIDServer-${UNRAID_VERSION}-Linux-${TARGET_KERNEL_VERSION}-x86_64"
ZIP_OUT="$OUT_DIR/${PACKAGE_NAME}.zip"
VERIFY_DIR="$BUILD_DIR/verify-$KERNEL_RELEASE"

[ -s "$ZIP_OUT" ] || die "Missing output zip: $ZIP_OUT"
[ -s "$OUT_DIR/bzroot-$KERNEL_RELEASE" ] || die "Missing custom bzroot"
[ -s "$OUT_DIR/bzimage-$KERNEL_RELEASE" ] || die "Missing custom bzimage"

if [ -d "$VERIFY_DIR" ]; then
  find "$VERIFY_DIR" -depth -type f -delete
  find "$VERIFY_DIR" -depth -type l -delete
  find "$VERIFY_DIR" -depth -type d -empty -delete
fi
mkdir -p "$VERIFY_DIR"
python3 "$SCRIPT_DIR/unpack-bzroot.py" "$OUT_DIR/bzroot-$KERNEL_RELEASE" "$VERIFY_DIR"

MODULE_DIR="$VERIFY_DIR/lib/modules/$KERNEL_RELEASE"
[ -d "$MODULE_DIR" ] || die "Repacked bzroot does not contain $KERNEL_RELEASE"

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

SPL_MODULE="$MODULE_DIR/extra/spl.ko.xz"
ZFS_MODULE="$MODULE_DIR/extra/zfs.ko.xz"

verify_module "$SPL_MODULE" "$ZFS_VERSION-1"
verify_module "$ZFS_MODULE" "$ZFS_VERSION-1"
verify_xz_crc32 "$SPL_MODULE"
verify_xz_crc32 "$ZFS_MODULE"
verify_module_compiler "$SPL_MODULE"
verify_module_compiler "$ZFS_MODULE"

DEPMOD_REPORT="$OUT_DIR/depmod-$KERNEL_RELEASE.txt"
depmod -e -b "$VERIFY_DIR" -F "$KERNEL_DIR/System.map" "$KERNEL_RELEASE" > "$DEPMOD_REPORT" 2>&1
[ ! -s "$DEPMOD_REPORT" ] || die "depmod reported unresolved symbols; see $DEPMOD_REPORT"

VMLINUX_VERIFY="$VERIFY_DIR/vmlinux.verify"
"$KERNEL_DIR/scripts/extract-vmlinux" "$OUT_DIR/bzimage-$KERNEL_RELEASE" > "$VMLINUX_VERIFY"
KERNEL_BANNER="$(strings "$VMLINUX_VERIFY" | awk '!found && /^Linux version / { print; found=1 }')"
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

[ "$(sha256sum "$OUT_DIR/bzmodules" | awk '{print $1}')" = "$(unzip -p "$UNRAID_ZIP" bzmodules | sha256sum | awk '{print $1}')" ] || die "bzmodules differs from official Unraid $UNRAID_VERSION"
unzip -tq "$ZIP_OUT"

{
  printf 'kernel_release=%s\n' "$KERNEL_RELEASE"
  printf 'kernel_banner=%s\n' "$KERNEL_BANNER"
  printf 'kernel_compiler=%s\n' "$KERNEL_COMPILER"
  printf 'zfs_version=%s\n' "$(modinfo -F version "$ZFS_MODULE")"
  printf 'zfs_compiler=%s\n' "$(module_compiler "$ZFS_MODULE" | paste -sd ';' -)"
  printf 'module_count=%s\n' "$(find "$MODULE_DIR" -type f -name '*.ko*' | wc -l)"
} > "$OUT_DIR/verification-$KERNEL_RELEASE.txt"

log "Static verification passed; report: $OUT_DIR/verification-$KERNEL_RELEASE.txt"
