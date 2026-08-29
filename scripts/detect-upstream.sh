#!/usr/bin/env bash
# Detect the latest upstream versions relevant to this project and emit a
# single JSON document on stdout:
#
#   {
#     "unraid":   { "version", "url", "sha256", "branch", "size" },
#     "official": { "kernel", "gcc", "error" },
#     "kernel":   { "release", "archive_url", "archive_sha256", "ready" }
#   }
#
# Sources:
#   1. Unraid OS: official releases JSON (latest public version, including
#      beta/rc builds). This is the *package base*: its userspace, firmware
#      and bzmodules are kept as-is. Its GCC version (extracted from the
#      release zip's bzimage via HTTP Range requests, ~9 MB) drives the
#      build toolchain.
#   2. ich777/unraid_kernel: latest GitHub release. This is the *kernel
#      version* that gets built and swapped into the official package.
#
# The i915 SR-IOV driver was extracted into a separate plugin package and is
# no longer tracked or built here.
#
# Environment:
#   GITHUB_TOKEN  optional, used to authenticate GitHub API requests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UA="Mozilla/5.0 (compatible; UnraidUpstreamWatcher/1.0; +https://github.com/hellomrli/my-unraid-kernel)"

UNRAID_RELEASES_URL="${UNRAID_RELEASES_URL:-https://releases.unraid.net/json?includePublic=1}"
ICH777_API_URL="${ICH777_API_URL:-https://api.github.com/repos/ich777/unraid_kernel/releases/latest}"

api_get() {
  local url="$1"
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsSL --max-time 60 -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "User-Agent: ${UA}" "$url"
  else
    curl -fsSL --max-time 60 -A "$UA" "$url"
  fi
}

# ---------------------------------------------------------------------------
# 1. Latest public Unraid OS version (stable or prerelease).
# ---------------------------------------------------------------------------
unraid_json="$(curl -fsSL --max-time 60 -A "$UA" "$UNRAID_RELEASES_URL")"

IFS='|' read -r UNRAID_VERSION UNRAID_URL UNRAID_SHA256 UNRAID_CHANGELOG \
        UNRAID_BRANCH UNRAID_SIZE <<< "$(UNRAID_JSON="$unraid_json" python3 - <<'PYEOF'
import json, os, re, sys
from functools import cmp_to_key

data = json.loads(os.environ["UNRAID_JSON"])

def parse(v):
    parts = []
    for raw in re.split(r"[-.]", v):
        mb = re.fullmatch(r"beta(\d+)", raw)
        mr = re.fullmatch(r"rc(\d+)", raw)
        if raw == "beta":
            parts.append(-2)
        elif raw == "rc":
            parts.append(-1)
        elif mb:
            parts += [-2, int(mb.group(1))]
        elif mr:
            parts += [-1, int(mr.group(1))]
        else:
            try:
                parts.append(int(raw))
            except ValueError:
                parts.append(0)
    return parts

def cmpv(a, b):
    ap, bp = parse(a), parse(b)
    n = max(len(ap), len(bp))
    for i in range(n):
        d = (bp[i] if i < len(bp) else 0) - (ap[i] if i < len(ap) else 0)
        if d:
            return d
    return 0

public = [r for r in data if r.get("public", True) is not False]
if not public:
    sys.exit("no public Unraid releases found")
latest = sorted(public, key=cmp_to_key(lambda a, b: cmpv(a["version"], b["version"])))[0]

url = (latest.get("url") or "").split("?")[0]
if not url:
    # Prereleases carry no direct url, but the changelog path on
    # next.dl.unraid.net exposes the same hash-pinned directory.
    changelog = latest.get("changelog") or ""
    if changelog.endswith(".txt"):
        url = changelog[:-4] + ".zip"
print("|".join([
    latest["version"],
    url,
    latest.get("sha256") or "",
    latest.get("changelog") or "",
    latest.get("branch") or "stable",
    latest.get("size") or "",
]))
PYEOF
)"

if [ -z "$UNRAID_VERSION" ]; then
  echo "detect-upstream: failed to resolve latest Unraid version" >&2
  exit 1
fi
if [ -z "$UNRAID_URL" ]; then
  echo "detect-upstream: no downloadable zip for Unraid $UNRAID_VERSION" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Official GCC toolchain (plus kernel version for reference), read from the
#    official bzimage.
# ---------------------------------------------------------------------------
OFFICIAL_KERNEL=""
OFFICIAL_GCC=""
OFFICIAL_ERROR=""
# The range-request extraction spans several HTTP calls; a single transient
# failure would otherwise skip a whole build day, so retry once.
gcc_out=""
for _attempt in 1 2; do
  if gcc_out="$("$SCRIPT_DIR/extract-official-gcc.py" --url "$UNRAID_URL" 2>/dev/null)"; then
    break
  fi
  gcc_out=""
  sleep 3
done
if [ -n "$gcc_out" ]; then
  OFFICIAL_KERNEL="$(sed -n 's/^kernel=//p' <<<"$gcc_out")"
  OFFICIAL_GCC="$(sed -n 's/^gcc=//p' <<<"$gcc_out")"
else
  OFFICIAL_ERROR="could not extract gcc/kernel from official zip"
fi

# ---------------------------------------------------------------------------
# 3. ich777/unraid_kernel: latest release = the kernel version to build.
# ---------------------------------------------------------------------------
ICH777_TAG=""
ICH777_ARCHIVE_URL=""
ICH777_ARCHIVE_SHA256=""
ICH777_READY=false
if ich777_json="$(api_get "$ICH777_API_URL")"; then
  ICH777_TAG="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])' <<<"$ich777_json")"
fi
if [ -n "$ICH777_TAG" ]; then
  ICH777_ARCHIVE_URL="https://github.com/ich777/unraid_kernel/releases/download/${ICH777_TAG}/linux-${ICH777_TAG}.tar.xz"
  if sha_line="$(curl -fsSL --max-time 60 -A "$UA" \
        "https://github.com/ich777/unraid_kernel/releases/download/${ICH777_TAG}/linux-${ICH777_TAG}.tar.xz.sha256" 2>/dev/null)"; then
    ICH777_ARCHIVE_SHA256="$(awk '{print $1}' <<<"$sha_line")"
    [ -n "$ICH777_ARCHIVE_SHA256" ] && ICH777_READY=true
  fi
fi

# ---------------------------------------------------------------------------
# Emit the result as JSON.
# ---------------------------------------------------------------------------
UNRAID_VERSION="$UNRAID_VERSION" UNRAID_URL="$UNRAID_URL" \
UNRAID_SHA256="$UNRAID_SHA256" UNRAID_BRANCH="$UNRAID_BRANCH" \
UNRAID_SIZE="$UNRAID_SIZE" OFFICIAL_KERNEL="$OFFICIAL_KERNEL" \
OFFICIAL_GCC="$OFFICIAL_GCC" OFFICIAL_ERROR="$OFFICIAL_ERROR" \
ICH777_TAG="$ICH777_TAG" ICH777_ARCHIVE_URL="$ICH777_ARCHIVE_URL" \
ICH777_ARCHIVE_SHA256="$ICH777_ARCHIVE_SHA256" ICH777_READY="$ICH777_READY" \
python3 - <<'PYEOF'
import json, os

print(json.dumps({
    "unraid": {
        "version": os.environ["UNRAID_VERSION"],
        "url": os.environ["UNRAID_URL"],
        "sha256": os.environ["UNRAID_SHA256"],
        "branch": os.environ["UNRAID_BRANCH"],
        "size": os.environ["UNRAID_SIZE"],
    },
    "official": {
        "kernel": os.environ["OFFICIAL_KERNEL"],
        "gcc": os.environ["OFFICIAL_GCC"],
        "error": os.environ["OFFICIAL_ERROR"],
    },
    "kernel": {
        "release": os.environ["ICH777_TAG"],
        "archive_url": os.environ["ICH777_ARCHIVE_URL"],
        "archive_sha256": os.environ["ICH777_ARCHIVE_SHA256"],
        "ready": os.environ["ICH777_READY"] == "true",
    },
}, indent=2))
PYEOF
