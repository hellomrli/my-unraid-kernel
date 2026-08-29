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

import os
import subprocess
import sys

ZSTD_MAGIC = b"\x28\xb5\x2f\xfd"
CPIO_END = b"TRAILER!!!"
GZIP_MAGIC = b"\x1f\x8b"


def extract(payload, decompressor, dst):
    """Run decompressor on payload and extract the resulting cpio into dst."""
    dec = subprocess.Popen(
        decompressor, stdin=subprocess.PIPE, stdout=subprocess.PIPE
    )
    out, _ = dec.communicate(payload)
    if dec.returncode != 0:
        sys.exit(
            "unpack-bzroot: decompressor failed: %s" % " ".join(decompressor)
        )
    cpio = subprocess.run(
        ["cpio", "--quiet", "-idm", "--no-absolute-filenames"],
        input=out,
        cwd=dst,
    )
    if cpio.returncode != 0:
        sys.exit("unpack-bzroot: cpio extraction failed (exit %d)" % cpio.returncode)


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: unpack-bzroot.py INITRAMFS-FILE DIRECTORY")
    src, dst = sys.argv[1], sys.argv[2]
    data = open(src, "rb").read()
    os.makedirs(dst, exist_ok=True)

    # The zstd member follows the uncompressed early cpio; only search past
    # the first end-of-archive marker so file contents cannot confuse us.
    trailer = data.find(CPIO_END)
    search_from = trailer + len(CPIO_END) if trailer >= 0 else 0
    zpos = data.find(ZSTD_MAGIC, search_from)

    if zpos > 0:
        early, main = data[:zpos], data[zpos:]
        extract(early, ["cat"], dst)
        extract(main, ["zstd", "-dc", "-q"], dst)
    elif data[:4] == ZSTD_MAGIC:
        sys.exit(
            "unpack-bzroot: whole-file zstd initramfs is not supported; "
            "expected an uncompressed early cpio followed by a zstd member"
        )
    elif data[:2] == GZIP_MAGIC:
        # Legacy/unexpected whole-file gzip archive.
        extract(data, ["gzip", "-dc"], dst)
    else:
        # Whole file is a single (uncompressed) cpio archive.
        extract(data, ["cat"], dst)


if __name__ == "__main__":
    main()
