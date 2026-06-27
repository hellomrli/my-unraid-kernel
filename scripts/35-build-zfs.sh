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
[ -f "$KERNEL_DIR/Module.symvers" ] || die "Missing Module.symvers. Run scripts/20-build-kernel.sh first."
[ -d "$MODULE_STAGE/lib/modules" ] || die "Missing module staging area. Run scripts/20-build-kernel.sh first."
[ -f "$ZFS_TARBALL" ] || die "Missing OpenZFS tarball. Run scripts/01-fetch-sources.sh first."

KREL="$(kernel_release)"

if [ ! -d "$ZFS_DIR" ]; then
  log "Extracting OpenZFS $ZFS_VERSION"
  tar -xf "$ZFS_TARBALL" -C "$BUILD_DIR"
fi

[ -x "$ZFS_DIR/configure" ] || die "Missing executable configure script in $ZFS_DIR"

log "Configuring OpenZFS $ZFS_VERSION modules for $KREL"
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

log "Building OpenZFS $ZFS_VERSION modules for $KREL"
make -C "$ZFS_DIR" -j"$JOBS" 2>&1 | tee "$LOG_DIR/build-zfs.log"

[ -f "$ZFS_DIR/module/spl.ko" ] || die "OpenZFS build did not produce spl.ko"
[ -f "$ZFS_DIR/module/zfs.ko" ] || die "OpenZFS build did not produce zfs.ko"

log "Installing OpenZFS modules into extra/"
install -d "$MODULE_STAGE/lib/modules/$KREL/extra"
cp -f "$ZFS_DIR/module/spl.ko" "$MODULE_STAGE/lib/modules/$KREL/extra/spl.ko"
cp -f "$ZFS_DIR/module/zfs.ko" "$MODULE_STAGE/lib/modules/$KREL/extra/zfs.ko"
xz -T0 -9 -f "$MODULE_STAGE/lib/modules/$KREL/extra/spl.ko" "$MODULE_STAGE/lib/modules/$KREL/extra/zfs.ko"

depmod -b "$MODULE_STAGE" -F "$KERNEL_DIR/System.map" "$KREL"

find "$MODULE_STAGE/lib/modules/$KREL/extra" -maxdepth 1 -type f | sort > "$OUT_DIR/zfs-installed-modules.txt"
log "Installed ZFS modules list: $OUT_DIR/zfs-installed-modules.txt"
