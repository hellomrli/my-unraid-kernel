#!/usr/bin/env python3
"""Generate the container-safe build environment for the auto-latest target.

Reads the parameters from the AUTO_PARAMS environment variable (JSON produced
by the watch-upstream workflow) and prints a build.env on stdout. CC/HOSTCC/
CXX/HOSTCXX are written as plain gcc/g++ because the build job always runs in
the official GCC container; the workflow re-derives EXPECTED_CC_VERSION from
the actual container compiler.
"""

import json
import os
import sys

params = json.loads(os.environ.get("AUTO_PARAMS") or "")
if not params:
    sys.exit("AUTO_PARAMS is empty or invalid")

kernel_release = params["kernel_release"]
if kernel_release.endswith("-Unraid"):
    target_kernel = kernel_release[: -len("-Unraid")]
else:
    target_kernel = kernel_release


def line(k, v):
    print(f"{k}={v}")


line("UNRAID_VERSION", params["unraid_version"])
line("TARGET_KERNEL_VERSION", target_kernel)
line("KERNEL_RELEASE", kernel_release)
line("JOBS", "all")
line("PLUGIN_ONLY", "false")
line("KERNEL_ARCHIVE_URL", params["kernel_archive_url"])
line("KERNEL_ARCHIVE_SHA256", params["kernel_archive_sha256"])
line("UNRAID_ZIP_URL", params["unraid_zip_url"])
line("UNRAID_ZIP_SHA256", params.get("unraid_zip_sha256", ""))
line("I915_SRIOV_REPO", "https://github.com/strongtz/i915-sriov-dkms.git")
line("I915_SRIOV_REF", params["i915_sriov_ref"])
line("I915_SRIOV_COMMIT", params.get("i915_sriov_commit", ""))
line("I915_MAX_VFS", "7")
line("PACKAGE_BUILD", "1")
line("ZFS_VERSION", "2.4.3")
line("ZFS_TARBALL_URL",
     "https://github.com/openzfs/zfs/releases/download/zfs-2.4.3/zfs-2.4.3.tar.gz")
line("ZFS_TARBALL_SHA256",
     "1f08f2d154f5189b5f1382848a32667b3d34066145b474c49cd3d41a5fba59a7")
line("FORCE_PREPARE", "false")
# The auto build consumes the official kernel and its module tree as-is:
# REBUILD_KERNEL=false, USE_STOCK_BZIMAGE=true, MERGE_STOCK_MODULES=true and
# USE_STOCK_ZFS=true keep the official package byte-compatible and only
# inject the four SR-IOV driver modules.
line("REBUILD_KERNEL", "false")
line("CLEAN_KERNEL_BUILD", "false")
line("CLEAN_ZFS_BUILD", "false")
line("USE_STOCK_BZIMAGE", "true")
line("MERGE_STOCK_MODULES", "true")
line("USE_STOCK_ZFS", "true")
line("EXPECTED_CC_VERSION", "0")
line("CC", "gcc")
line("HOSTCC", "gcc")
line("CXX", "g++")
line("HOSTCXX", "g++")
