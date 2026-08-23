#!/usr/bin/env python3
"""Compare detected upstream versions against the last built state.

Usage:
    upstream-compare.py upstream.json config/upstream-state.env

Reads the JSON produced by scripts/detect-upstream.sh and the state file
tracked in the repository. When the GITHUB_ENV environment variable is set
(GitHub Actions), the NEED_BUILD / DETECTED_* / LAST_* lines are appended to
it; a short human summary is always printed on stdout.

A new build is requested when any of the three upstream sources moved past
the last built state AND every build ingredient is resolvable right now:
    1. the official Unraid OS version,
    2. the official kernel release (extracted from the official bzimage),
    3. the ich777/unraid_kernel latest release tag.
"""

import json
import os
import re
import sys
from functools import cmp_to_key


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


def newer(a, b):
    # True when a is strictly newer than b (an empty b counts as old).
    return bool(a) and a != b and cmpv(a, b) < 0


def load_state(path):
    state = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, _, v = line.partition("=")
                state[k.strip()] = v.strip()
    return state


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: upstream-compare.py upstream.json config/upstream-state.env")
    up = json.load(open(sys.argv[1]))
    state = load_state(sys.argv[2])

    new_unraid = newer(up["unraid"]["version"], state.get("LAST_UNRAID_VERSION", ""))
    new_kernel = newer(up["official"]["kernel"], state.get("LAST_KERNEL_RELEASE", ""))
    new_ich777 = newer(up["kernel"]["release"], state.get("LAST_ICH777_RELEASE", ""))

    # A build is only useful when every ingredient is resolvable right now:
    # a downloadable official zip, the official kernel/gcc from its bzimage,
    # and the matching ich777 kernel archive with checksum.
    ready = bool(
        up["unraid"]["version"] and up["unraid"]["url"]
        and up["official"]["kernel"] and up["official"]["gcc"]
        and up["kernel"]["ready"] and up["kernel"]["archive_sha256"]
    )
    need_build = (new_unraid or new_kernel or new_ich777) and ready

    lines = [
        f"NEED_BUILD={'true' if need_build else 'false'}",
        f"DETECTED_UNRAID={up['unraid']['version']}",
        f"DETECTED_KERNEL={up['official']['kernel']}",
        f"DETECTED_ICH777={up['kernel']['release']}",
        f"DETECTED_OFFICIAL_GCC={up['official']['gcc']}",
        f"LAST_UNRAID={state.get('LAST_UNRAID_VERSION', '')}",
        f"LAST_KERNEL={state.get('LAST_KERNEL_RELEASE', '')}",
        f"LAST_ICH777={state.get('LAST_ICH777_RELEASE', '')}",
        f"MIN_GCC={state.get('MIN_GCC_VERSION', '15.3.0')}",
    ]
    github_env = os.environ.get("GITHUB_ENV")
    if github_env:
        with open(github_env, "a") as out:
            out.write("\n".join(lines) + "\n")

    print(
        f"new_unraid={new_unraid} new_kernel={new_kernel} new_ich777={new_ich777} "
        f"ready={ready} need_build={need_build}"
    )


if __name__ == "__main__":
    main()
