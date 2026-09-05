#!/usr/bin/env python3
"""Unpack an Unraid bzroot initramfs without depending on unmkinitramfs.

The official Unraid bzroot (and the bzroot repacked by 40-package-unraid.sh)
is a concatenation of two cpio archives:

    [uncompressed newc cpio: early kernel payload]
    [zstd-compressed newc cpio: everything else]

Debian's unmkinitramfs (initramfs-tools-core <= 0.142, as shipped in the
official GCC container images) does not handle this layout reliably, while
Ubuntu's C rewrite (initramfs-tools-bin) does.  This script reimplements the
minimal splitting logic with stdlib only, feeding each member to GNU cpio.

Usage: unpack-bzroot.py INITRAMFS-FILE DIRECTORY
"""

import subprocess
import sys
from pathlib import Path

from bzroot import ZSTD_MAGIC, cpio_records, read_main, split_bzroot

GZIP_MAGIC = b"\x1f\x8b"


def archives(data):
    """Validate every member before extracting anything to the filesystem."""
    if data.startswith(GZIP_MAGIC):
        main = subprocess.run(["gzip", "-dc"], input=data,
                              stdout=subprocess.PIPE, check=True).stdout
        read_main(main)
        return (main,)
    if data.startswith(ZSTD_MAGIC):
        raise ValueError("whole-file zstd initramfs is not supported; "
                         "expected an uncompressed early cpio followed by a zstd member")
    _, _, end = cpio_records(data)
    if not any(data[end:]):
        return (data,)
    early, main = split_bzroot(data)
    read_main(main)
    return early, main


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: unpack-bzroot.py INITRAMFS-FILE DIRECTORY")
    src, dst = map(Path, sys.argv[1:])
    try:
        members = archives(src.read_bytes())
        dst.mkdir(parents=True, exist_ok=True)
        for payload in members:
            subprocess.run(["cpio", "--quiet", "-idm", "--no-absolute-filenames",
                            "--no-preserve-owner"], input=payload, cwd=dst, check=True)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f"unpack-bzroot: {error}")


if __name__ == "__main__":
    main()
