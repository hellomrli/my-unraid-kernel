#!/usr/bin/env python3
"""Verify the complete Unraid package and every module before publication."""

import argparse
import concurrent.futures
import hashlib
import json
import lzma
import re
import struct
import sys
import zipfile
from pathlib import Path

BOOT_FILES = ("bzimage", "bzroot")
REPLACED_ENTRIES = {*BOOT_FILES, *(name + ".sha256" for name in BOOT_FILES)}


def stream_hash(stream):
    digest = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
        digest.update(chunk)
    return digest.hexdigest()


def file_hash(path):
    with path.open("rb") as stream:
        return stream_hash(stream)


def zip_entries(archive):
    entries = {}
    for info in archive.infolist():
        if info.filename in entries:
            raise ValueError(f"duplicate ZIP entry: {info.filename}")
        entries[info.filename] = info
    return entries


def check_sidecar(data, expected, label):
    # rc.S consumes a bare hash. Do not accept sha256sum's filename format.
    # Leading whitespace would shift the first 64 bytes checked at boot.
    if data[:64] != expected.encode("ascii") or data[64:].strip():
        raise ValueError(f"boot sidecar checksum mismatch: {label}")


def check_manifest(path, expected):
    actual = {}
    for line in path.read_text().splitlines():
        match = re.fullmatch(r"([0-9a-f]{64}) [ *](.+)", line)
        if not match:
            raise ValueError(f"invalid checksum manifest line in {path.name}: {line!r}")
        digest, name = match.groups()
        if name in actual:
            raise ValueError(f"duplicate checksum manifest entry: {name}")
        actual[name] = digest
    if actual != expected:
        changed = sorted(name for name in actual.keys() | expected.keys()
                         if actual.get(name) != expected.get(name))
        raise ValueError(f"checksum manifest mismatch in {path.name}: {', '.join(changed)}")


def verify_package(official_zip, package, release):
    out = package.parent
    hashes = {}
    with zipfile.ZipFile(official_zip) as original, zipfile.ZipFile(package) as rebuilt:
        old_entries, new_entries = zip_entries(original), zip_entries(rebuilt)
        if old_entries.keys() != new_entries.keys():
            changed = sorted(old_entries.keys() ^ new_entries.keys())
            raise ValueError(f"ZIP file set differs from official: {', '.join(changed[:10])}")
        if not REPLACED_ENTRIES <= old_entries.keys() or "bzmodules" not in old_entries:
            raise ValueError("official ZIP is missing required boot files")
        kept = 0
        # Reading every entry also verifies ZIP CRCs, including firmware and
        # userspace that must stay byte-identical to the official release.
        for name in old_entries:
            if name in REPLACED_ENTRIES:
                continue
            with original.open(name) as old, rebuilt.open(name) as new:
                original_hash = stream_hash(old)
                if original_hash != stream_hash(new):
                    raise ValueError(f"official ZIP entry changed: {name}")
            if name == "bzmodules":
                hashes[name] = original_hash
                if file_hash(out / name) != original_hash:
                    raise ValueError("standalone bzmodules differs from official")
            kept += 1
        for name in BOOT_FILES:
            with rebuilt.open(name) as stream:
                digest = stream_hash(stream)
            for filename in (name, f"{name}-{release}"):
                if file_hash(out / filename) != digest:
                    raise ValueError(f"ZIP and standalone boot file differ: {filename}")
                hashes[filename] = digest
            sidecar = name + ".sha256"
            check_sidecar(rebuilt.read(sidecar), digest, f"ZIP/{sidecar}")
            check_sidecar((out / sidecar).read_bytes(), digest, sidecar)
    hashes[package.name] = file_hash(package)
    check_manifest(out / (package.name + ".sha256"), {package.name: hashes[package.name]})
    check_manifest(out / f"sha256sums-{release}.txt", {
        name: hashes[name] for name in
        (f"bzimage-{release}", f"bzroot-{release}", "bzmodules", package.name)
    })
    return {
        "unchanged_official_zip_entries": kept,
        "only_replaced_zip_entries": sorted(REPLACED_ENTRIES),
        "sha256": hashes,
    }


def elf_sections(data):
    """Read bounded ELF64 section data; kernel targets in this repo are x86_64."""
    if len(data) < 64 or data[:7] != b"\x7fELF\x02\x01\x01":
        raise ValueError("not an ELF64 little-endian module")
    if struct.unpack_from("<HHI", data, 16) != (1, 62, 1):
        raise ValueError("not an x86_64 relocatable ELF module")
    offset = struct.unpack_from("<Q", data, 40)[0]
    size, count, strings_index = struct.unpack_from("<HHH", data, 58)
    if size != 64 or not 0 < strings_index < count or offset < 64 or offset + count * size > len(data):
        raise ValueError("invalid or truncated ELF section table")
    sections = [struct.unpack_from("<IIQQQQIIQQ", data, offset + i * size)
                for i in range(count)]

    def contents(section):
        start, length = section[4:6]
        if start + length > len(data):
            raise ValueError("ELF section extends beyond end of file")
        return data[start:start + length]

    if sections[strings_index][1] != 3:
        raise ValueError("invalid ELF section-name string table")
    names = contents(sections[strings_index])
    result = {}
    for section in sections:
        start = section[0]
        end = names.find(b"\0", start)
        if start >= len(names) or end < 0:
            raise ValueError("invalid ELF section name")
        name = names[start:end]
        if section[1] == 8:  # SHT_NOBITS has no file payload (e.g. .bss).
            continue
        payload = contents(section)
        if name in (b".modinfo", b".comment") and name in result:
            raise ValueError(f"duplicate ELF section: {name!r}")
        result[name] = payload
    return result


def check_module(path, release, expected_gcc):
    try:
        if path.is_symlink() or not path.is_file() or not path.name.endswith(".ko.xz"):
            raise ValueError("expected a regular .ko.xz module")
        stream = lzma.LZMADecompressor(format=lzma.FORMAT_XZ)
        raw = stream.decompress(path.read_bytes())
        if not stream.eof or stream.unused_data:
            raise ValueError("truncated module or trailing data after XZ stream")
        if stream.check != lzma.CHECK_CRC32:
            raise ValueError("kernel module must use XZ CRC32")
        sections = elf_sections(raw)
        info = {}
        for field in sections.get(b".modinfo", b"").split(b"\0"):
            key, separator, value = field.partition(b"=")
            if separator:
                info.setdefault(key, []).append(value)
        vermagic = info.get(b"vermagic", [])
        if len(vermagic) != 1 or not vermagic[0].startswith((release + " ").encode()):
            raise ValueError(f"wrong or missing vermagic (expected {release})")
        compilers = sorted({field.decode("utf-8", "replace")
                            for field in sections.get(b".comment", b"").split(b"\0")
                            if field.startswith(b"GCC: ")})
        if expected_gcc:
            version = re.compile(r"(?:^|\s)" + re.escape(expected_gcc) + r"(?=\s|$)")
            if not compilers or any(not version.search(marker) for marker in compilers):
                raise ValueError(f"wrong or missing compiler (expected GCC {expected_gcc}): {compilers}")
        return info, compilers
    except (OSError, ValueError, lzma.LZMAError) as error:
        raise ValueError(f"{path}: {error}") from error


def verify_modules(root, release, zfs_version, expected_gcc, builtin_md=False):
    module_root = root / "lib/modules"
    tree = module_root / release
    if sorted(path.name for path in module_root.iterdir()) != [release] or tree.is_symlink() or not tree.is_dir():
        raise ValueError(f"expected exactly one module directory: {release}")
    for name in ("build", "source"):
        path = tree / name
        if not path.is_symlink() or str(path.readlink()) != f"/usr/src/linux-{release}":
            raise ValueError(f"wrong module {name} link for {release}")
    modules = sorted(tree.rglob("*.ko*"))
    if not modules:
        raise ValueError("no kernel modules found")
    # Check completeness as well as the ABI of the modules that are present.
    order = (tree / "modules.order").read_text().splitlines()
    if not order or len(set(order)) != len(order):
        raise ValueError("empty or duplicate entries in modules.order")
    actual = {path.relative_to(tree).as_posix().removesuffix(".xz")
              for path in modules if path.relative_to(tree).parts[0] == "kernel"}
    if actual != set(order):
        changed = sorted(actual ^ set(order))
        raise ValueError(f"in-tree module inventory differs from modules.order: {', '.join(changed[:10])}")
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(lambda path: check_module(path, release, expected_gcc), modules))
    checked = {path.relative_to(tree).as_posix(): result
               for path, result in zip(modules, results)}
    for name in ("spl", "zfs"):
        info, _ = checked.get(f"extra/{name}.ko.xz", ({}, []))
        if info.get(b"version") != [(zfs_version + "-1").encode()]:
            raise ValueError(f"wrong or missing OpenZFS {name} module version")
    md_description = "built into bzimage" if builtin_md else ""
    if not builtin_md:
        info, _ = checked.get("kernel/drivers/md/md-mod.ko.xz", ({}, []))
        md_description = b"; ".join(info.get(b"description", [])).decode("utf-8", "replace")
        if "unraid" not in md_description.lower():
            raise ValueError("md-mod is missing the Unraid array driver")
    return {
        "verified_module_count": len(modules),
        "module_checks": ["ELF64 x86_64", "vermagic", "XZ CRC32", "modules.order"]
                         + (["GCC version"] if expected_gcc else []),
        "expected_gcc_version": expected_gcc or None,
        "module_compilers": sorted({marker for _, markers in results for marker in markers}),
        "unraid_md_description": md_description,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--official-zip", type=Path, required=True)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--root", type=Path, required=True, help="extracted rebuilt bzroot")
    parser.add_argument("--kernel-config", type=Path, required=True)
    parser.add_argument("--kernel-release", required=True)
    parser.add_argument("--unraid-version", required=True)
    parser.add_argument("--zfs-version", required=True)
    parser.add_argument("--expected-gcc", default="")
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    try:
        args.report.unlink(missing_ok=True)
        version = (args.root / "etc/unraid-version").read_text().strip()
        if version != f'version="{args.unraid_version}"':
            raise ValueError(f"wrong Unraid userspace version: {version}")
        config = set(args.kernel_config.read_text().splitlines())
        if "CONFIG_MD_UNRAID=y" not in config or not config & {"CONFIG_BLK_DEV_MD=y", "CONFIG_BLK_DEV_MD=m"}:
            raise ValueError("kernel configuration is missing the Unraid array driver")
        report = {
            "unraid_version": args.unraid_version,
            "kernel_release": args.kernel_release,
            "zfs_version": args.zfs_version + "-1",
            **verify_modules(args.root, args.kernel_release, args.zfs_version,
                             args.expected_gcc, "CONFIG_BLK_DEV_MD=y" in config),
            **verify_package(args.official_zip, args.package, args.kernel_release),
            "boot_and_hardware_tests": "not performed",
        }
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        sys.exit(f"verify-artifacts: {error}")
    print(f"Verified {report['verified_module_count']} modules and preserved "
          f"{report['unchanged_official_zip_entries']} official ZIP entries; report: {args.report}")


if __name__ == "__main__":
    main()
