#!/usr/bin/env python3
"""Replace only lib/modules in Unraid's early-newc + zstd-newc initramfs.

Keep the early archive and all other newc records verbatim, including owners,
permissions, hard links and device nodes. No privileged extraction is needed.
"""

import argparse
import subprocess
from pathlib import Path

from bzroot import is_module_path, read_main, split_bzroot


def replace_modules(main, modules):
    original, trailer = read_main(main)
    replacement, _ = read_main(modules)
    if not replacement or any(not is_module_path(name) for name, _ in replacement):
        raise ValueError("replacement archive must contain only lib/modules")
    kept = [raw for name, raw in original if not is_module_path(name)]
    # newc identifies hard links by inode and device. Give replacement entries
    # fresh inode numbers so staging filesystem inodes cannot alias stock ones.
    next_ino = max((int(raw[6:14], 16) for raw in kept), default=0) + 1
    inodes = {}
    for _, raw in replacement:
        identity = (raw[6:14], raw[62:78])
        if identity not in inodes:
            if next_ino > 0xffffffff:
                raise ValueError("no free newc inode numbers")
            inodes[identity] = next_ino
            next_ino += 1
        kept.append(raw[:6] + f"{inodes[identity]:08x}".encode() + raw[14:])
    result = b"".join(kept) + trailer
    return result + b"\0" * (-len(result) % 512)


def verify(original, rebuilt):
    old_early, old_main = split_bzroot(original)
    new_early, new_main = split_bzroot(rebuilt)
    if old_early != new_early:
        raise ValueError("early archive changed")
    def stock_records(main):
        records, _ = read_main(main)
        return [(name, raw) for name, raw in records if not is_module_path(name)]
    old_records, new_records = stock_records(old_main), stock_records(new_main)
    before, after = dict(old_records), dict(new_records)
    changed = sorted(name for name in before.keys() | after.keys()
                     if before.get(name) != after.get(name))
    if changed:
        raise ValueError(f"non-module initramfs records changed: {', '.join(changed[:10])}")
    if old_records != new_records:
        raise ValueError("non-module initramfs record order changed")
    return len(before)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", action="store_true",
                        help="compare original and rebuilt bzroot without writing")
    parser.add_argument("original", type=Path)
    parser.add_argument("replacement", type=Path,
                        help="modules newc archive, or rebuilt bzroot with --verify")
    parser.add_argument("output", type=Path, nargs="?")
    args = parser.parse_args()
    if args.verify:
        if args.output:
            parser.error("--verify takes only original and rebuilt bzroot")
        count = verify(args.original.read_bytes(), args.replacement.read_bytes())
        print(f"Preserved early archive and {count} non-module newc records")
        return
    if args.output is None:
        parser.error("output bzroot is required")
    early, original_main = split_bzroot(args.original.read_bytes())
    main_cpio = replace_modules(original_main, args.replacement.read_bytes())
    with args.output.open("wb") as out:
        out.write(early)
        out.flush()
        subprocess.run(["zstd", "-19", "-T0", "-q", "-c"], input=main_cpio,
                       stdout=out, check=True)


if __name__ == "__main__":
    main()
