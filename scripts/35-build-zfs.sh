#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

need_cmd depmod
need_cmd make
need_cmd tar
need_cmd xz

[ -d "$KERNEL_DIR" ] || die "Missing prepared kernel tree. Run scripts/10-prepare-kernel.sh first."
[ -f "$KERNEL_DIR/Module.symvers" ] || die "Missing Module.symvers"
[ -d "$MODULE_STAGE/lib/modules/$KERNEL_RELEASE" ] || die "Missing module stage"
[ -f "$ZFS_TARBALL" ] || die "Missing OpenZFS tarball. Run scripts/01-fetch-sources.sh first."
check_kernel_release

if [ "$CLEAN_ZFS_BUILD" = "true" ] && [ -d "$ZFS_DIR" ]; then
  log "Removing prior OpenZFS objects"
  find "$ZFS_DIR" -depth -type f -delete
  find "$ZFS_DIR" -depth -type l -delete
  find "$ZFS_DIR" -depth -type d -empty -delete
fi

if [ ! -d "$ZFS_DIR" ]; then
  log "Extracting OpenZFS $ZFS_VERSION"
  tar -xf "$ZFS_TARBALL" -C "$BUILD_DIR"
fi

[ -x "$ZFS_DIR/configure" ] || die "Missing executable configure script in $ZFS_DIR"

log "Configuring OpenZFS $ZFS_VERSION modules for $KERNEL_RELEASE"
(
  cd "$ZFS_DIR"
  ./configure \
    --with-config=kernel \
    --with-linux="$KERNEL_DIR" \
    --with-linux-obj="$KERNEL_DIR" \
    --enable-linux-experimental \
    --prefix=/usr \
    --libdir=/lib64 2>&1 | tee "$LOG_DIR/configure-zfs.log"
)

log "Building OpenZFS $ZFS_VERSION modules for $KERNEL_RELEASE"
make -C "$ZFS_DIR" \
  CC="$CC" \
  HOSTCC="$HOSTCC" \
  CXX="$CXX" \
  HOSTCXX="$HOSTCXX" \
  -j"$JOBS" 2>&1 | tee "$LOG_DIR/build-zfs.log"

[ -s "$ZFS_DIR/module/spl.ko" ] || die "OpenZFS build did not produce spl.ko"
[ -s "$ZFS_DIR/module/zfs.ko" ] || die "OpenZFS build did not produce zfs.ko"

EXTRA_DIR="$MODULE_STAGE/lib/modules/$KERNEL_RELEASE/extra"
install -d "$EXTRA_DIR"
install -m 0644 "$ZFS_DIR/module/spl.ko" "$EXTRA_DIR/spl.ko"
install -m 0644 "$ZFS_DIR/module/zfs.ko" "$EXTRA_DIR/zfs.ko"
xz -T0 -9 --check=crc32 -f "$EXTRA_DIR/spl.ko" "$EXTRA_DIR/zfs.ko"

depmod -b "$MODULE_STAGE" -F "$KERNEL_DIR/System.map" "$KERNEL_RELEASE"
find "$EXTRA_DIR" -maxdepth 1 -type f -printf '%P\n' | sort > "$OUT_DIR/zfs-installed-modules.txt"
log "Installed OpenZFS $ZFS_VERSION modules"
