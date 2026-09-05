"""Shared parsing for Unraid's early-newc + zstd-newc initramfs."""

import subprocess
from pathlib import PurePosixPath

ZSTD_MAGIC = b"\x28\xb5\x2f\xfd"


def cpio_records(data):
    """Return (named raw records, trailer, end offset) for one newc archive."""
    records = []
    seen = set()
    pos = 0
    while True:
        if len(data) < pos + 110 or data[pos:pos + 6] not in (b"070701", b"070702"):
            raise ValueError(f"invalid or truncated newc header at {pos}")
        fields = [int(data[pos + 6 + i * 8:pos + 14 + i * 8], 16) for i in range(13)]
        size, namesize = fields[6], fields[11]
        name_end = pos + 110 + namesize
        content = (name_end + 3) & ~3
        end = (content + size + 3) & ~3
        if namesize < 1 or name_end > len(data) or end > len(data) or data[name_end - 1] != 0:
            raise ValueError(f"invalid or truncated newc entry at {pos}")
        if data[pos:pos + 6] == b"070702":
            if (sum(data[content:content + size]) & 0xffffffff) != fields[12]:
                raise ValueError(f"newc checksum mismatch at {pos}")
        name = data[pos + 110:name_end - 1].decode("utf-8", "surrogateescape")
        raw = data[pos:end]
        if name == "TRAILER!!!":
            if size:
                raise ValueError("newc trailer has a payload")
            return records, raw, end
        path = PurePosixPath(name)
        if path.is_absolute() or ".." in path.parts or "\0" in name:
            raise ValueError(f"unsafe newc path: {name!r}")
        name = str(path)
        if name in seen:
            raise ValueError(f"duplicate newc path: {name}")
        seen.add(name)
        records.append((name, raw))
        pos = end


def is_module_path(name):
    return name == "lib/modules" or name.startswith("lib/modules/")


def split_bzroot(data):
    early_records, _, end = cpio_records(data)
    if any(is_module_path(name) for name, _ in early_records):
        raise ValueError("unexpected module tree in early archive")
    while end < len(data) and data[end] == 0:
        end += 1
    if data[end:end + 4] != ZSTD_MAGIC:
        raise ValueError("expected early newc archive followed by a zstd archive")
    main = subprocess.run(["zstd", "-dcq"], input=data[end:],
                          stdout=subprocess.PIPE, check=True).stdout
    return data[:end], main


def read_main(data):
    records, trailer, end = cpio_records(data)
    if any(data[end:]):
        raise ValueError("unexpected data after newc trailer")
    return records, trailer
