#!/usr/bin/env python3
"""Extract the GCC version used to build the official Unraid kernel.

The official Unraid release zip stores its kernel image as an uncompressed
(stored) ``bzimage`` member.  This script fetches only the pieces it needs
via HTTP Range requests (the zip central directory plus the bzimage bytes),
decompresses the bzImage payload and reads the ``Linux version ...`` string
which contains the ``gcc (GCC) X.Y.Z`` marker.

Usage:
    extract-official-gcc.py --url  https://releases.unraid.net/dl/stable/.../unRAIDServer-....zip
    extract-official-gcc.py --zip  /path/to/unRAIDServer-....zip

Prints one line per detected field::

    gcc=15.3.0
    kernel=6.18.38-Unraid
    version=6.18.38-Unraid (root@Develop) ...
"""

import argparse
import bz2
import gzip
import io
import lzma
import re
import struct
import sys
import urllib.request
import zipfile

GCC_RE = re.compile(rb"gcc \(GCC\) ([0-9]+\.[0-9]+(?:\.[0-9]+)?)")
LINUX_VERSION_RE = re.compile(rb"Linux version ([^\s]+)")

TAIL_BYTES = 512 * 1024  # enough for the EOCD + central directory

UA = "Mozilla/5.0 (compatible; UnraidUpstreamWatcher/1.0; +https://github.com/hellomrli/my-unraid-kernel)"


def http_get(url, headers=None, timeout=300):
    req = urllib.request.Request(
        url, headers={"User-Agent": UA, **(headers or {})})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def http_range(url, start, end, timeout=300):
    """Fetch ``url[start:end]`` (end exclusive) via a Range request."""
    return http_get(
        url, headers={"Range": f"bytes={start}-{end - 1}"}, timeout=timeout)


def zip_central_directory(data: bytes):
    """Return (central_directory_offset, central_directory_size)."""
    eocd = data.rfind(b"PK\x05\x06")
    if eocd < 0:
        raise RuntimeError("zip end-of-central-directory record not found")
    # EOCD layout: sig(4) disk(2) cd_disk(2) n_disk(2) n_total(2)
    #              cd_size(4) cd_offset(4) comment_len(2)
    cd_size, cd_offset = struct.unpack_from("<II", data, eocd + 12)
    return cd_offset, cd_size


def iter_central_dir(data, cd_offset, cd_size):
    pos = cd_offset
    end = cd_offset + cd_size
    while pos < end:
        if data[pos:pos + 4] != b"PK\x01\x02":
            raise RuntimeError(f"bad central directory signature at {pos}")
        # sig(4) ver(2) ver_need(2) flags(2) method(2) time(2) date(2)
        # crc(4) csize(4) usize(4) name_len(2) extra_len(2) comment_len(2)
        # disk(2) iattr(2) eattr(4) local_offset(4)
        name_len, extra_len, comment_len = struct.unpack_from(
            "<HHH", data, pos + 28)
        local_offset = struct.unpack_from("<I", data, pos + 42)[0]
        name = data[pos + 46:pos + 46 + name_len].decode("utf-8", "replace")
        yield name, local_offset
        pos += 46 + name_len + extra_len + comment_len


def read_zip_member(url, member_name, total_size):
    """Read one uncompressed member out of a remote zip using Range requests."""
    tail = http_range(url, max(0, total_size - TAIL_BYTES), total_size)
    cd_offset, cd_size = zip_central_directory(tail)
    base = max(0, total_size - TAIL_BYTES)
    if cd_offset < base or cd_offset + cd_size > base + len(tail):
        # Central directory does not fully fit in the tail; refetch precisely.
        full = http_range(url, cd_offset, cd_offset + cd_size)
        cd_data = full
        cd_base = cd_offset
    else:
        cd_data = tail[cd_offset - base:cd_offset - base + cd_size]
        cd_base = cd_offset

    target = None
    for name, local_offset in iter_central_dir(cd_data, 0, len(cd_data)):
        if name == member_name:
            target = local_offset
            break
    if target is None:
        raise RuntimeError(f"member {member_name!r} not found in zip")

    # Local file header: sig(4) ver(2) flags(2) method(2) time(2) date(2)
    # crc(4) csize(4) usize(4) name_len(2) extra_len(2)
    header = http_range(url, target, target + 64)
    if header[:4] != b"PK\x03\x04":
        raise RuntimeError(f"bad local header at {target}")
    method = struct.unpack_from("<H", header, 8)[0]
    csize = struct.unpack_from("<I", header, 18)[0]
    usize = struct.unpack_from("<I", header, 22)[0]
    name_len, extra_len = struct.unpack_from("<HH", header, 26)
    data_start = target + 30 + name_len + extra_len
    data = http_range(url, data_start, data_start + csize)
    if method == 0:  # stored
        assert len(data) == usize
        return data
    if method == 8:  # deflate
        import zlib
        return zlib.decompress(data, -15)
    raise RuntimeError(f"unsupported zip compression method {method}")


def decompress_bzimage(payload: bytes):
    """Return the decompressed vmlinux bytes, trying common kernel formats."""

    def try_decompress(chunk, kind):
        try:
            if kind == "lzma":
                return lzma.decompress(chunk, format=lzma.FORMAT_ALONE)
            if kind == "xz":
                return lzma.decompress(chunk, format=lzma.FORMAT_XZ)
            if kind == "gzip":
                return gzip.decompress(chunk)
            if kind == "bzip2":
                return bz2.decompress(chunk)
        except Exception:
            return None
        return None

    # LZMA-alone payloads are not self-identifying; scan for the LZMA
    # properties byte (0x5d) followed by three zero bytes (the same header
    # the kernel's own scripts/extract-vmlinux searches for).
    candidates = []
    idx = 0
    while True:
        idx = payload.find(b"\x5d\x00\x00\x00", idx)
        if idx < 0:
            break
        candidates.append(("lzma", payload[idx:]))
        idx += 4
    candidates.append(("xz", payload))
    candidates.append(("gzip", payload))
    candidates.append(("bzip2", payload))

    for kind, chunk in candidates:
        out = try_decompress(chunk, kind)
        if out and b"Linux version" in out:
            return out
    raise RuntimeError("could not decompress bzImage payload")


def main():
    ap = argparse.ArgumentParser()
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--url", help="URL of the official Unraid zip")
    src.add_argument("--zip", help="local path of the official Unraid zip")
    args = ap.parse_args()

    if args.zip:
        with zipfile.ZipFile(args.zip) as zf:
            info = zf.getinfo("bzimage")
            if info.compress_type != zipfile.ZIP_STORED:
                raise RuntimeError("local zip bzimage is not stored")
            payload = zf.read("bzimage")
    else:
        # Determine the total size with a tiny Range request instead of HEAD;
        # some CDNs are stricter about HEAD but still honor Range. Do not read
        # the body: a server that ignores Range would otherwise be pulled in
        # full for no benefit.
        total = None
        try:
            req = urllib.request.Request(
                args.url,
                headers={"User-Agent": UA, "Range": "bytes=0-0"},
                method="GET")
            with urllib.request.urlopen(req, timeout=60) as resp:
                cr = resp.headers.get("Content-Range") or ""
                total = int(cr.split("/")[-1]) if "/" in cr else None
        except Exception:
            total = None
        if not total:
            raise RuntimeError(
                "zip URL did not report a total size via Content-Range; "
                "the server may not support range requests")
        payload = read_zip_member(args.url, "bzimage", total)

    vmlinux = decompress_bzimage(payload)

    gcc_m = GCC_RE.search(vmlinux)
    ver_m = LINUX_VERSION_RE.search(vmlinux)
    if gcc_m:
        print(f"gcc={gcc_m.group(1).decode()}")
    if ver_m:
        print(f"kernel={ver_m.group(1).decode()}")
    if not gcc_m:
        print("gcc=", file=sys.stderr)
        raise SystemExit(2)


if __name__ == "__main__":
    main()
