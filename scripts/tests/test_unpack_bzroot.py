import gzip
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from test_repack_bzroot import ZSTD_MAGIC, archive, bzroot, entry

SCRIPT = Path(__file__).resolve().parents[1] / "unpack-bzroot.py"


class UnpackTests(unittest.TestCase):
    def unpack(self, data, base):
        source = base / "bzroot"
        source.write_bytes(data)
        return subprocess.run([sys.executable, str(SCRIPT), str(source), str(base / "root")],
                              capture_output=True, text=True)

    def test_embedded_trailer_and_compression_magic_are_file_contents(self):
        microcode = b"TRAILER!!!" + ZSTD_MAGIC + b"not an archive boundary"
        data = bzroot(archive(entry("kernel/microcode", microcode)),
                      archive(entry("etc/example", b"main archive")))
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            result = self.unpack(data, base)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((base / "root/kernel/microcode").read_bytes(), microcode)
            self.assertEqual((base / "root/etc/example").read_bytes(), b"main archive")

    def test_legacy_gzip_and_plain_cpio(self):
        data = archive(entry("etc/example", b"TRAILER!!!" + ZSTD_MAGIC))
        for payload in (data, gzip.compress(data)):
            with self.subTest(gzip=payload != data), tempfile.TemporaryDirectory() as temp:
                base = Path(temp)
                result = self.unpack(payload, base)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual((base / "root/etc/example").read_bytes(), b"TRAILER!!!" + ZSTD_MAGIC)

    def test_malformed_main_archive_is_rejected_before_any_extraction(self):
        early = archive(entry("kernel/microcode", b"valid early data"))
        for main in (b"070701", archive(entry("../escape", b"escape")),
                     archive(entry("etc/example")) + b"unexpected data"):
            with self.subTest(main=main[:20]), tempfile.TemporaryDirectory() as temp:
                base = Path(temp)
                result = self.unpack(bzroot(early, main), base)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((base / "root").exists())
                self.assertFalse((base / "escape").exists())


if __name__ == "__main__":
    unittest.main()
