import hashlib
import importlib.util
import lzma
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import warnings
import zipfile

SCRIPT = Path(__file__).resolve().parents[1] / "verify-artifacts.py"
spec = importlib.util.spec_from_file_location("verify_artifacts", SCRIPT)
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)
RELEASE = "7.2.3-Unraid"


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.out = self.base / "out"
        self.out.mkdir()
        self.official = self.base / "official.zip"
        self.package = self.out / "rebuilt.zip"
        self.stock = {"bzimage": b"old kernel", "bzroot": b"old initramfs",
                      "bzmodules": b"official userspace", "bzfirmware": b"official firmware",
                      "syslinux/": b"", "syslinux/syslinux.cfg": b"boot config"}
        for name in ("bzimage", "bzroot"):
            self.stock[name + ".sha256"] = hashlib.sha256(self.stock[name]).hexdigest().encode() + b"\n"
        self.entries = dict(self.stock)
        for name, data in (("bzimage", b"new kernel"), ("bzroot", b"new initramfs")):
            self.entries[name] = data
            self.entries[name + ".sha256"] = hashlib.sha256(data).hexdigest().encode() + b"\n"
            for filename in (name, f"{name}-{RELEASE}"):
                (self.out / filename).write_bytes(data)
            (self.out / (name + ".sha256")).write_bytes(self.entries[name + ".sha256"])
        (self.out / "bzmodules").write_bytes(self.stock["bzmodules"])
        self.write_zip(self.official, self.stock)
        self.write_zip(self.package, self.entries)
        names = [f"bzimage-{RELEASE}", f"bzroot-{RELEASE}", "bzmodules", self.package.name]
        self.manifest = "".join(f"{hashlib.sha256((self.out / name).read_bytes()).hexdigest()}  {name}\n"
                                for name in names)
        (self.out / f"sha256sums-{RELEASE}.txt").write_text(self.manifest)
        (self.out / "rebuilt.zip.sha256").write_text(self.manifest.splitlines(keepends=True)[-1])

    def write_zip(self, path, entries):
        with zipfile.ZipFile(path, "w") as archive:
            for name, data in entries.items():
                archive.writestr(name, data)

    def check(self):
        return verify.verify_package(self.official, self.package, RELEASE)

    def test_complete_package_matches_official_and_downloads(self):
        report = self.check()
        self.assertEqual(report["unchanged_official_zip_entries"], 4)
        self.assertEqual(report["sha256"]["bzroot"], hashlib.sha256(b"new initramfs").hexdigest())

    def test_rejects_changed_userspace_or_firmware(self):
        for name in ("bzmodules", "bzfirmware", "syslinux/syslinux.cfg"):
            with self.subTest(name=name):
                self.write_zip(self.package, {**self.entries, name: b"changed"})
                with self.assertRaisesRegex(ValueError, "official ZIP entry changed"):
                    self.check()

    def test_rejects_duplicate_or_missing_zip_entries(self):
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(self.package, "a") as archive:
                archive.writestr("bzroot", b"duplicate")
        with self.assertRaisesRegex(ValueError, "duplicate ZIP entry"):
            self.check()
        self.write_zip(self.package, {name: data for name, data in self.entries.items() if name != "bzfirmware"})
        with self.assertRaisesRegex(ValueError, "ZIP file set"):
            self.check()

    def test_rejects_stale_standalone_boot_file(self):
        (self.out / f"bzroot-{RELEASE}").write_bytes(b"last build")
        with self.assertRaisesRegex(ValueError, "standalone boot file differ"):
            self.check()

    def test_rejects_wrong_boot_sidecars_inside_and_outside_zip(self):
        invalid = (b"0" * 64 + b"\n", b" " + self.entries["bzroot.sha256"],
                   b"\n" + self.entries["bzroot.sha256"],
                   self.entries["bzroot.sha256"].strip() + b"  bzroot\n")
        for data in invalid:
            for zipped in (False, True):
                with self.subTest(zipped=zipped, sidecar=data):
                    self.write_zip(self.package, self.entries)
                    (self.out / "bzroot.sha256").write_bytes(self.entries["bzroot.sha256"])
                    if zipped:
                        self.write_zip(self.package, {**self.entries, "bzroot.sha256": data})
                    else:
                        (self.out / "bzroot.sha256").write_bytes(data)
                    with self.assertRaisesRegex(ValueError, "boot sidecar checksum"):
                        self.check()

    def test_rejects_stale_incomplete_and_duplicate_checksum_manifests(self):
        path = self.out / f"sha256sums-{RELEASE}.txt"
        for text in (self.manifest.replace(self.manifest[:64], "0" * 64),
                     "\n".join(self.manifest.splitlines()[:-1]) + "\n",
                     self.manifest + self.manifest.splitlines(keepends=True)[0]):
            with self.subTest(manifest=text):
                path.write_text(text)
                with self.assertRaisesRegex(ValueError, "checksum manifest"):
                    self.check()

    def test_failed_cli_invalidates_previous_report(self):
        root = self.base / "root"
        (root / "etc").mkdir(parents=True)
        (root / "etc/unraid-version").write_text('version="wrong"\n')
        report = self.out / "verification.json"
        report.write_text('{"old_result": "passed"}\n')
        result = subprocess.run([
            sys.executable, str(SCRIPT), "--official-zip", str(self.official),
            "--package", str(self.package), "--root", str(root),
            "--kernel-config", str(self.base / "config"), "--kernel-release", RELEASE,
            "--unraid-version", "7.4.0-beta.2", "--zfs-version", "2.4.4", "--report", str(report),
        ], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("wrong Unraid userspace", result.stderr)
        self.assertFalse(report.exists())


class ModuleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Use a real compiler/ELF object so the fixture does not reproduce the
        # section-table parsing code that is being tested.
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "module.o"
            source = r'''
__attribute__((section(".modinfo"), used)) static const char metadata[] =
    "vermagic=7.2.3-Unraid SMP \0version=2.4.4-1\0"
    "description=unRAID array stacking driver";
int init_module(void) { return 0; }
'''
            subprocess.run(["gcc", "-c", "-x", "c", "-o", str(path), "-"],
                           input=source.encode(), capture_output=True, check=True)
            cls.raw = path.read_bytes()
        cls.gcc = subprocess.check_output(["gcc", "-dumpfullversion", "-dumpversion"], text=True).strip()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.path = self.base / "module.ko.xz"

    def write_module(self, raw=None, check=lzma.CHECK_CRC32, path=None):
        target = path or self.path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(lzma.compress(self.raw if raw is None else raw, check=check))
        return target

    def check(self):
        return verify.check_module(self.path, RELEASE, self.gcc)

    def test_accepts_real_elf_with_matching_metadata(self):
        self.write_module()
        info, compilers = self.check()
        self.assertEqual(info[b"version"], [b"2.4.4-1"])
        self.assertTrue(compilers)

    def test_rejects_wrong_vermagic_and_gcc(self):
        self.write_module(self.raw.replace(b"7.2.3-Unraid", b"7.2.2-Unraid"))
        with self.assertRaisesRegex(ValueError, "vermagic"):
            self.check()
        self.write_module()
        with self.assertRaisesRegex(ValueError, "compiler"):
            verify.check_module(self.path, RELEASE, self.gcc + "1")

    def test_compiler_strings_outside_comment_section_do_not_count(self):
        self.write_module(self.raw.replace(b"GCC: ", b"BAD: ") + b"GCC: (GNU) " + self.gcc.encode() + b"\0")
        with self.assertRaisesRegex(ValueError, "compiler"):
            self.check()

    def test_rejects_wrong_xz_check_truncation_and_trailing_data(self):
        self.write_module(check=lzma.CHECK_CRC64)
        with self.assertRaisesRegex(ValueError, "XZ CRC32"):
            self.check()
        compressed = self.write_module().read_bytes()
        for damaged in (compressed[:-10], compressed + b"trailing", compressed + compressed):
            with self.subTest(size=len(damaged)):
                self.path.write_bytes(damaged)
                with self.assertRaisesRegex(ValueError, "XZ stream"):
                    self.check()

    def test_rejects_non_elf_and_truncated_elf(self):
        for raw in (b"not an ELF", self.raw[:100]):
            with self.subTest(size=len(raw)):
                self.write_module(raw)
                with self.assertRaisesRegex(ValueError, "ELF"):
                    self.check()

    def make_module_tree(self):
        tree = self.base / "lib/modules" / RELEASE
        order = "kernel/drivers/md/md-mod.ko"
        self.write_module(path=tree / (order + ".xz"))
        for name in ("spl", "zfs"):
            self.write_module(path=tree / f"extra/{name}.ko.xz")
        (tree / "modules.order").write_text(order + "\n")
        for name in ("build", "source"):
            (tree / name).symlink_to(f"/usr/src/linux-{RELEASE}")
        return tree

    def test_complete_module_tree_checks_inventory_and_unraid_md(self):
        tree = self.make_module_tree()
        report = verify.verify_modules(self.base, RELEASE, "2.4.4", self.gcc)
        self.assertEqual(report["verified_module_count"], 3)
        self.assertEqual(report["unraid_md_description"], "unRAID array stacking driver")
        (tree / "kernel/drivers/md/md-mod.ko.xz").unlink()
        with self.assertRaisesRegex(ValueError, "inventory"):
            verify.verify_modules(self.base, RELEASE, "2.4.4", self.gcc)

    def test_rejects_wrong_zfs_and_vanilla_md(self):
        tree = self.make_module_tree()
        zfs = tree / "extra/zfs.ko.xz"
        self.write_module(self.raw.replace(b"version=2.4.4-1", b"version=2.4.5-1"), path=zfs)
        with self.assertRaisesRegex(ValueError, "OpenZFS zfs"):
            verify.verify_modules(self.base, RELEASE, "2.4.4", self.gcc)
        self.write_module(path=zfs)
        self.write_module(self.raw.replace(b"unRAID", b"vanill"), path=tree / "kernel/drivers/md/md-mod.ko.xz")
        with self.assertRaisesRegex(ValueError, "Unraid array driver"):
            verify.verify_modules(self.base, RELEASE, "2.4.4", self.gcc)

    def test_rejects_leftover_module_tree_and_wrong_source_link(self):
        tree = self.make_module_tree()
        extra = tree.parent / "old-release"
        extra.mkdir()
        with self.assertRaisesRegex(ValueError, "exactly one"):
            verify.verify_modules(self.base, RELEASE, "2.4.4", self.gcc)
        extra.rmdir()
        (tree / "source").unlink()
        (tree / "source").symlink_to("/usr/src/old-release")
        with self.assertRaisesRegex(ValueError, "source link"):
            verify.verify_modules(self.base, RELEASE, "2.4.4", self.gcc)


if __name__ == "__main__":
    unittest.main()
