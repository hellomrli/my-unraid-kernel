#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

need_cmd mksquashfs
need_cmd sha256sum

[ -f "$KERNEL_DIR/arch/x86/boot/bzImage" ] || die "Missing built bzImage. Run scripts/20-build-kernel.sh first."
[ -d "$MODULE_STAGE/lib/modules" ] || die "Missing module staging area. Run scripts/20-build-kernel.sh first."

KREL="$(kernel_release)"

log "Packaging bzimage"
cp "$KERNEL_DIR/arch/x86/boot/bzImage" "$OUT_DIR/bzimage-${KREL}"
cp "$KERNEL_DIR/arch/x86/boot/bzImage" "$OUT_DIR/bzimage"

log "Packaging bzmodules as squashfs"
rm -f "$OUT_DIR/bzmodules-${KREL}" "$OUT_DIR/bzmodules"
mksquashfs "$MODULE_STAGE" "$OUT_DIR/bzmodules-${KREL}" -noappend -comp xz -b 1M 2>&1 | tee "$LOG_DIR/package-bzmodules.log"
cp "$OUT_DIR/bzmodules-${KREL}" "$OUT_DIR/bzmodules"

cat > "$OUT_DIR/syslinux-append-i915-sriov.txt" <<EOF
intel_iommu=on i915.enable_guc=3 i915.max_vfs=${I915_MAX_VFS} module_blacklist=xe
EOF

(
  cd "$OUT_DIR"
  sha256sum "bzimage-${KREL}" "bzmodules-${KREL}" > "sha256sums-${KREL}.txt"
)

log "Output:"
log "  $OUT_DIR/bzimage"
log "  $OUT_DIR/bzmodules"
log "  $OUT_DIR/syslinux-append-i915-sriov.txt"
log "Keep the original Unraid USB files backed up before replacing bzimage/bzmodules."
