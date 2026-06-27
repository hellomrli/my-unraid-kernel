#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

need_cmd make
need_cmd tar

[ -s "$KERNEL_TARBALL" ] || die "Missing $KERNEL_TARBALL. Run scripts/01-fetch-sources.sh first."

if [ -d "$KERNEL_DIR" ]; then
  if [ "$FORCE_PREPARE" = "true" ]; then
    log "Removing existing prepared kernel tree"
    rm -rf "$KERNEL_DIR"
  else
    die "$KERNEL_DIR already exists. Set FORCE_PREPARE=true in config/build.env to recreate it."
  fi
fi

log "Extracting Linux $TARGET_KERNEL_VERSION"
tar -xf "$KERNEL_TARBALL" -C "$BUILD_DIR"
[ -d "$KERNEL_DIR" ] || die "Expected extracted directory not found: $KERNEL_DIR"

if [ ! -s "$BASE_CONFIG_PATH" ]; then
  if [ -s "$BASE_KERNEL_ARCHIVE" ]; then
    log "Extracting baseline Unraid config from $(basename "$BASE_KERNEL_ARCHIVE")"
    config_member="$(tar -tf "$BASE_KERNEL_ARCHIVE" | grep '/\.config$' | head -n 1 || true)"
    if [ -n "$config_member" ]; then
      tar -xOf "$BASE_KERNEL_ARCHIVE" "$config_member" > "$BASE_CONFIG_PATH"
    fi
  fi

  if [ ! -s "$BASE_CONFIG_PATH" ] && [ -d "$ROOT_DIR/$THOR_REPO_DIR/.git" ]; then
    log "Using thor2002ro fallback config $THOR_CONFIG_FILE"
    git -C "$ROOT_DIR/$THOR_REPO_DIR" show "HEAD:$THOR_CONFIG_FILE" > "$BASE_CONFIG_PATH"
  fi
fi

[ -s "$BASE_CONFIG_PATH" ] || die "No baseline config available"

log "Applying baseline config"
cp "$BASE_CONFIG_PATH" "$KERNEL_DIR/.config"

cd "$KERNEL_DIR"

scripts/config --file .config --set-str LOCALVERSION "$LOCALVERSION"
scripts/config --file .config --disable LOCALVERSION_AUTO
scripts/config --file .config --enable PCI_IOV
scripts/config --file .config --module VFIO
scripts/config --file .config --module VFIO_PCI
scripts/config --file .config --enable VFIO_PCI_VGA
scripts/config --file .config --enable VFIO_PCI_IGD
scripts/config --file .config --module INTEL_MEI
scripts/config --file .config --module INTEL_MEI_ME
scripts/config --file .config --module INTEL_MEI_GSC
scripts/config --file .config --module INTEL_MEI_HDCP
scripts/config --file .config --module INTEL_MEI_PXP
scripts/config --file .config --module INTEL_MEI_GSC_PROXY
scripts/config --file .config --module DRM_I915
scripts/config --file .config --enable DRM_I915_GVT
scripts/config --file .config --module DRM_I915_GVT_KVMGT
scripts/config --file .config --module DRM_XE
scripts/config --file .config --set-str DRM_XE_FORCE_PROBE "*"

log "Running olddefconfig"
make olddefconfig

cp .config "$ROOT_DIR/config/generated-linux-${TARGET_KERNEL_VERSION}${LOCALVERSION}.config"
log "Prepared $KERNEL_DIR"
