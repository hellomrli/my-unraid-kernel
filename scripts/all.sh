#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

"$SCRIPT_DIR/00-check-env.sh"
"$SCRIPT_DIR/01-fetch-sources.sh"
"$SCRIPT_DIR/10-prepare-kernel.sh"
"$SCRIPT_DIR/20-build-kernel.sh"
"$SCRIPT_DIR/35-build-zfs.sh"
"$SCRIPT_DIR/40-package-unraid.sh"
"$SCRIPT_DIR/50-verify.sh"
