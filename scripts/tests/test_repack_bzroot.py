import importlib.util
from pathlib import Path
import stat
import subprocess
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from bzroot import ZSTD_MAGIC, read_main

spec = importlib.util.spec_from_file_location(
    "repack_bzroot", Path(__file__).resolve().parents[1] / "repack-bzroot.py")
repack = importlib.util.module_from_spec(spec)
spec.loader.exec_module(repack)


def entry(name, data=b"", *, ino=1, uid=0, gid=0, mode=stat.S_IFREG | 0o644, nlink=1):
    name = name.encode() + b"\0"
    fields = [ino, mode, uid, gid, nlink, 1234567890, len(data), 0, 0, 0, 0, len(name), 0]
    record = b"070701" + b"".join(f"{v:08x}".encode() for v in fields) + name
    record += b"\0" * (-len(record) % 4)
    record += data
    return record + b"\0" * (-len(record) % 4)


def archive(*entries):
    data = b"".join(entries) + entry("TRAILER!!!")
    return data + b"\0" * (-len(data) % 512)


def bzroot(early, main):
    return early + subprocess.run(["zstd", "-q", "-c"], input=main,
                                  stdout=subprocess.PIPE, check=True).stdout


class RepackTests(unittest.TestCase):
    def test_module_replacement_preserves_all_stock_records(self):
        # Fixtures include non-root ownership, restricted modes, a symlink,
        # a device node and hard links with their data on the final entry.
        stock = [
            entry("var/lib/nfs/sm", uid=32, gid=32, mode=stat.S_IFDIR | 0o700),
            entry("etc/gshadow", b"test", gid=43, mode=stat.S_IFREG | 0o640),
            entry("etc/example", b"../target", uid=53, mode=stat.S_IFLNK | 0o777),
            entry("dev/console", mode=stat.S_IFCHR | 0o600),
            entry("bin/one", ino=99, nlink=2),
            entry("bin/two", b"linked content", ino=99, nlink=2),
        ]
        original = archive(*stock, entry("lib/modules/old/old.ko", b"old"))
        replacement = archive(entry("./lib/modules/new/new.ko", b"new", ino=99))
        result = repack.replace_modules(original, replacement)
        parsed, _ = repack.read_main(result)
        self.assertEqual([raw for name, raw in parsed if not repack.is_module_path(name)], stock)
        self.assertNotIn("lib/modules/old/old.ko", dict(parsed))
        module = dict(parsed)["lib/modules/new/new.ko"]
        self.assertGreater(int(module[6:14], 16), 99)
        # GNU cpio also accepts the result, independently of our newc parser.
        listed = subprocess.run(["cpio", "-it", "--quiet"], input=result,
                                stdout=subprocess.PIPE, check=True).stdout
        self.assertIn(b"lib/modules/new/new.ko", listed)

    def test_new_hardlinks_keep_their_shared_inode(self):
        original = archive(entry("etc/kept", b"keep", ino=100))
        replacement = archive(entry("lib/modules/new/a", ino=100, nlink=2),
                              entry("lib/modules/new/b", b"module", ino=100, nlink=2))
        parsed, _ = repack.read_main(repack.replace_modules(original, replacement))
        records = dict(parsed)
        self.assertEqual(records["lib/modules/new/a"][6:14], records["lib/modules/new/b"][6:14])
        self.assertNotEqual(records["etc/kept"][6:14], records["lib/modules/new/a"][6:14])

    def test_early_archive_is_preserved_even_with_embedded_magic(self):
        early = archive(entry("kernel/microcode", b"TRAILER!!!" + ZSTD_MAGIC))
        original_main = archive(entry("var/lib/dhcpcd", uid=68, gid=68, mode=stat.S_IFDIR | 0o750),
                                entry("lib/modules/old/a", b"old"))
        updated_main = repack.replace_modules(original_main, archive(entry("lib/modules/new/b", b"new")))
        original, updated = bzroot(early, original_main), bzroot(early, updated_main)
        self.assertEqual(repack.split_bzroot(updated)[0], early)
        self.assertEqual(repack.verify(original, updated), 1)

    def test_verifier_rejects_lost_ownership_and_changed_early_payload(self):
        early = archive(entry("kernel/microcode", b"microcode"))
        original = bzroot(early, archive(entry("var/lib/nfs", uid=32, gid=32)))
        with self.assertRaisesRegex(ValueError, "non-module"):
            repack.verify(original, bzroot(early, archive(entry("var/lib/nfs"))))
        with self.assertRaisesRegex(ValueError, "early archive"):
            repack.verify(original, bzroot(archive(entry("kernel/microcode", b"changed")),
                                          archive(entry("var/lib/nfs", uid=32, gid=32))))

    def test_rejects_unrelated_replacement_and_malformed_archives(self):
        with self.assertRaisesRegex(ValueError, "only lib/modules"):
            repack.replace_modules(archive(entry("etc/kept")), archive(entry("etc/changed")))
        for payload in [b"070701", entry("file", b"data")[:-4], archive(entry("../escape")),
                        archive(entry("file"), entry("./file")), archive(entry("file")) + b"extra"]:
            with self.subTest(payload=payload[:20]), self.assertRaises(ValueError):
                repack.read_main(payload)

    def test_verifier_rejects_reordered_stock_records(self):
        early = archive(entry("kernel/microcode", b"microcode"))
        first, second = entry("etc/one", b"one"), entry("etc/two", b"two")
        with self.assertRaisesRegex(ValueError, "record order"):
            repack.verify(bzroot(early, archive(first, second)),
                          bzroot(early, archive(second, first)))

    def test_crc_newc_checks_payload(self):
        record = entry("etc/example", b"payload")
        crc_record = b"070702" + record[6:102] + f"{sum(b'payload'):08x}".encode() + record[110:]
        self.assertEqual(read_main(archive(crc_record))[0][0][0], "etc/example")
        with self.assertRaisesRegex(ValueError, "checksum"):
            read_main(archive(crc_record.replace(b"payload", b"damaged")))


if __name__ == "__main__":
    unittest.main()
