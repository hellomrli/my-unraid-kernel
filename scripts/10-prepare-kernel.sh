#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

need_cmd make
need_cmd tar
need_cmd git

# Extract a kernel source archive into dest. ich777 releases are flat "./"
# archives; vanilla kernel.org tarballs carry a single top directory that
# must be stripped so both land as a flat tree.
extract_kernel_archive() {
  local archive="$1"
  local dest="$2"
  local listing first
  # Read the full listing first and take the first line via parameter
  # expansion: piping tar (or printf) into head triggers SIGPIPE (exit 141)
  # under pipefail once the output is large enough.
  listing="$(tar -tf "$archive")" || die "cannot list archive: $archive"
  first="${listing%%$'\n'*}"
  case "$first" in
    ./*) tar -xf "$archive" -C "$dest" ;;
    */*) tar -xf "$archive" --strip-components=1 -C "$dest" ;;
    *) tar -xf "$archive" -C "$dest" ;;
  esac
}

# Keep this outside the fresh-extraction path so an already prepared vanilla
# tree also receives newly ported hardware fixes when the scripts are updated.
# ACS override stays opt-in through pcie_acs_override=... at boot.
apply_unraid_hardware_ports() {
  local series="$ROOT_DIR/patches/linux-${TARGET_KERNEL_VERSION}-hardware.series"
  local patch_name port_patch
  [ "$REBUILD_KERNEL" = "true" ] || die "Vanilla Unraid ports require REBUILD_KERNEL=true"
  [ -s "$series" ] || die "Missing Unraid hardware patch series: $series"
  while IFS= read -r patch_name; do
    [ -n "$patch_name" ] || continue
    port_patch="$ROOT_DIR/patches/$patch_name"
    [ -s "$port_patch" ] || die "Missing Unraid hardware patch: $port_patch"
    if git -C "$KERNEL_DIR" apply --check "$port_patch" >/dev/null 2>&1; then
      git -C "$KERNEL_DIR" apply "$port_patch"
      log "Applied $patch_name"
    elif git -C "$KERNEL_DIR" apply --reverse --check "$port_patch" >/dev/null 2>&1; then
      log "$patch_name already applied"
    else
      die "Cannot apply $port_patch"
    fi
  done < "$series"
}

[ -s "$KERNEL_ARCHIVE" ] || die "Missing $KERNEL_ARCHIVE. Run scripts/01-fetch-sources.sh first."

if [ -d "$KERNEL_DIR" ]; then
  if [ "$FORCE_PREPARE" = "true" ]; then
    log "Removing existing prepared kernel tree"
    find "$KERNEL_DIR" -depth -type f -delete
    find "$KERNEL_DIR" -depth -type l -delete
    find "$KERNEL_DIR" -depth -type d -empty -delete
  else
    [ -s "$KERNEL_DIR/.config" ] || \
      die "$KERNEL_DIR exists but has no .config; re-run with FORCE_PREPARE=true"
    if [ -n "${SEED_KERNEL_ARCHIVE_URL:-}" ]; then
      apply_unraid_hardware_ports
    fi
    check_kernel_release
    log "Using prepared kernel tree $KERNEL_DIR"
    exit 0
  fi
fi

log "Extracting $KERNEL_RELEASE kernel tree"
mkdir -p "$KERNEL_DIR"
extract_kernel_archive "$KERNEL_ARCHIVE" "$KERNEL_DIR"

if [ -s "$KERNEL_DIR/.config" ]; then
  # ich777 prepared tree: shipped prebuilt, only needs consistency checks.
  [ -s "$KERNEL_DIR/Module.symvers" ] || die "Kernel archive did not contain Module.symvers"
  [ -s "$KERNEL_DIR/arch/x86/boot/bzImage" ] || die "Kernel archive did not contain bzImage"
  check_kernel_release

  cp "$KERNEL_DIR/.config" "$ROOT_DIR/config/generated-linux-${KERNEL_RELEASE}.config"
  log "Prepared prebuilt $KERNEL_RELEASE tree"
  exit 0
fi

# ---------------------------------------------------------------------------
# Vanilla kernel.org source mode. A bare mainline tree has no Unraid bits:
# seed it with the .config from an ich777 release and port Lime Technology's
# md driver (drivers/md/{md_unraid.c,md_unraid.h,unraid.c}, the array core
# that vanilla kernels lack) into the tree. CONFIG_LOCALVERSION="-Unraid"
# from the seed keeps the kernel release string consistent.
# ---------------------------------------------------------------------------
[ -s "$KERNEL_DIR/Makefile" ] || die "Kernel archive did not contain a kernel source tree"
[ -n "${SEED_KERNEL_ARCHIVE_URL:-}" ] || die "Vanilla source mode requires SEED_KERNEL_ARCHIVE_URL"
[ -n "${SEED_KERNEL_RELEASE:-}" ] || die "Vanilla source mode requires SEED_KERNEL_RELEASE"

SEED_ARCHIVE="$DOWNLOAD_DIR/seed-linux-${SEED_KERNEL_RELEASE}.tar.xz"
SEED_DIR="$BUILD_DIR/seed-linux-${SEED_KERNEL_RELEASE}"
download_file "$SEED_KERNEL_ARCHIVE_URL" "$SEED_ARCHIVE"
verify_sha256 "$SEED_ARCHIVE" "${SEED_KERNEL_ARCHIVE_SHA256:-}"

if [ ! -s "$SEED_DIR/.config" ]; then
  rm -rf "$SEED_DIR"
  mkdir -p "$SEED_DIR"
  extract_kernel_archive "$SEED_ARCHIVE" "$SEED_DIR"
fi
[ -s "$SEED_DIR/.config" ] || die "Seed archive did not contain .config"
for seed_file in md_unraid.c md_unraid.h unraid.c; do
  [ -s "$SEED_DIR/drivers/md/$seed_file" ] || die "Seed archive did not contain drivers/md/$seed_file"
done

log "Porting Lime Technology Unraid md driver from $SEED_KERNEL_RELEASE into $TARGET_KERNEL_VERSION"
install -m 0644 \
  "$SEED_DIR/drivers/md/md_unraid.c" \
  "$SEED_DIR/drivers/md/md_unraid.h" \
  "$SEED_DIR/drivers/md/unraid.c" \
  "$KERNEL_DIR/drivers/md/"

# The seed driver sources target the 6.18 Unraid tree; port them to the 7.x
# kernel APIs (raid6 direct functions instead of pointers, xor_blocks ->
# xor_gen, strscpy instead of the removed strncpy).
PORT_PATCH="$ROOT_DIR/patches/unraid-driver-linux-7.2.3-port.patch"
[ -s "$PORT_PATCH" ] || die "Missing Unraid driver port patch: $PORT_PATCH"
if git -C "$KERNEL_DIR" apply --check "$PORT_PATCH" >/dev/null 2>&1; then
  git -C "$KERNEL_DIR" apply "$PORT_PATCH"
  log "Applied Unraid driver port patch"
elif git -C "$KERNEL_DIR" apply --reverse --check "$PORT_PATCH" >/dev/null 2>&1; then
  log "Unraid driver port patch already applied"
else
  die "Cannot apply $PORT_PATCH"
fi

# Lime Technology builds their array core as a replacement for the vanilla
# md core: with CONFIG_MD_UNRAID=y the md-mod objects become md_unraid.o +
# unraid.o instead of md.o (+ bitmap variants). Reproduce that hook around
# whatever md-mod object list the target kernel ships.
python3 - "$KERNEL_DIR/drivers/md/Makefile" <<'PYEOF'
import re
import sys

path = sys.argv[1]
text = open(path).read()
if "CONFIG_MD_UNRAID" in text:
    print("md Makefile already ported")
    sys.exit(0)
lines = text.splitlines(keepends=True)
start = None
for i, line in enumerate(lines):
    if re.match(r"^md-mod-y\s*\+= md\.o\s*$", line):
        start = i
        break
if start is None:
    sys.exit("could not locate 'md-mod-y += md.o' in drivers/md/Makefile")
end = start
while end + 1 < len(lines) and re.match(r"^md-mod-", lines[end + 1]):
    end += 1
block = "".join(lines[start : end + 1])
hook = (
    "ifeq ($(CONFIG_MD_UNRAID),y)\n"
    "md-mod-y        += md_unraid.o unraid.o\n"
    "else\n"
    + block
    + "endif\n"
)
open(path, "w").write("".join(lines[:start]) + hook + "".join(lines[end + 1 :]))
print("md Makefile hook installed")

# The Lime Technology MD replacement also must suppress the vanilla
# md-autodetect object when MD is built in.  The experimental configuration
# uses a module, but keeping this guard makes the port safe for both modes.
text = open(path).read()
if "ifneq ($(CONFIG_MD_UNRAID),y)" not in text:
    pattern = re.compile(
        r"(?m)^ifeq \(\$\(CONFIG_BLK_DEV_MD\),y\)\n"
        r"obj-y\s+\+= md-autodetect\.o\nendif\n"
    )
    replacement = (
        "ifneq ($(CONFIG_MD_UNRAID),y)\n"
        "ifeq ($(CONFIG_BLK_DEV_MD),y)\n"
        "obj-y\t\t\t\t+= md-autodetect.o\n"
        "endif\n"
        "endif\n"
    )
    text, count = pattern.subn(replacement, text, count=1)
    if count != 1:
        sys.exit("could not guard md-autodetect.o in drivers/md/Makefile")
    open(path, "w").write(text)
    print("md-autodetect guard installed")
PYEOF

if ! grep -q '^config MD_UNRAID$' "$KERNEL_DIR/drivers/md/Kconfig"; then
  cat >> "$KERNEL_DIR/drivers/md/Kconfig" <<'EOF'

config MD_UNRAID
	bool "unRAID support"
	depends on MD
	depends on BLK_DEV_MD
	depends on !MD_AUTODETECT
	depends on !MD_LINEAR
	depends on !MD_RAID0
	depends on !MD_RAID1
	depends on !MD_RAID10
	depends on !MD_RAID456
	depends on !MD_MULTIPATH
	depends on !MD_FAULTY
	depends on !MD_CLUSTER
	select XOR_BLOCKS
	help
	  Lime Technology unRAID driver.
EOF
fi

# Preserve the beta.2 hardware fixes with contexts adapted to 7.2.3.
apply_unraid_hardware_ports

log "Seeding $TARGET_KERNEL_VERSION configuration from $SEED_KERNEL_RELEASE"
cp "$SEED_DIR/.config" "$KERNEL_DIR/.config"

log "Running olddefconfig for $TARGET_KERNEL_VERSION"
kmake olddefconfig

cp "$KERNEL_DIR/.config" "$ROOT_DIR/config/generated-linux-${KERNEL_RELEASE}.config"
check_kernel_release
log "Prepared vanilla $KERNEL_RELEASE tree with Unraid md and hardware ports"
