# Unraid i915 SR-IOV kernel builds

This repository publishes experimental Unraid kernels and i915 SR-IOV
packages. The default `main` branch contains the current 6.18 build. Build
inputs and verification notes are kept alongside the scripts and release
documents.

## Branches

| Branch | Contents |
| --- | --- |
| `main` | Unraid 7.3.2 with Linux `6.18.43-Unraid`, i915 SR-IOV `2026.08.08`, and OpenZFS 2.4.3. This is the former `6.18` branch. |
| `7.0` | The previous `main` history: the Unraid 7.3.1 / Linux 7.1.1 build. |

The `main` build is available from the GitHub Releases page. The release
assets include:

- `unRAIDServer-7.3.2-Linux-6.18.43-i915-sriov-2026.08.08-x86_64.zip`: a
  complete Unraid USB package, including the rebuilt `bzimage` and `bzroot`.
- `i915-sriov-20260808-6.18.43-Unraid-1.txz`: the plugin-compatible driver
  package for an existing 6.18.43-Unraid installation.
- SHA-256 and MD5 checksum files, plus the static verification report.

Use the complete ZIP when replacing the Unraid kernel. It keeps the official
`bzmodules`, `bzfirmware`, bootloader files, and configuration skeleton, and
replaces `bzimage` and `bzroot` together. Back up the original USB files and
keep a recovery boot entry before testing.

## Build

The tracked `config/build.env` pins the GCC 15.3.0 toolchain used for the
release. Run the complete build from this directory:

```bash
scripts/all.sh
```

The principal outputs are written to `out/`:

```text
out/unRAIDServer-7.3.2-Linux-6.18.43-i915-sriov-2026.08.08-x86_64.zip
out/i915-sriov-20260808-6.18.43-Unraid-1.txz
```

To build only the driver package for stock Unraid 7.3.2 / 6.18.38-Unraid:

```bash
BUILD_ENV_FILE=config/build-6.18.38-plugin.env scripts/all.sh
```

That mode uses the matching prebuilt kernel ABI and produces
`out/i915-sriov-20260808-6.18.38-Unraid-1.txz`.

## Boot and install

Use the i915 path and keep `xe` blacklisted:

```text
intel_iommu=on i915.enable_guc=3 i915.max_vfs=7 module_blacklist=xe
```

For the plugin package, verify the checksum and install it while i915 is not
loaded:

```sh
sha256sum -c i915-sriov-20260808-6.18.43-Unraid-1.txz.sha256
upgradepkg --install-new i915-sriov-20260808-6.18.43-Unraid-1.txz
depmod -a 6.18.43-Unraid
```

Reboot into the matching kernel, then check:

```sh
uname -r
modinfo i915 | egrep '^(version|vermagic|origin_kernel):'
```

Do not unload i915 from an active console or pass the physical-function GPU
through to a VM. If initialization fails, boot the recovery entry with
`module_blacklist=i915,xe`.

## Validation

The published 6.18.43 release passed module vermagic, compiler-marker, and
`depmod -e` checks. A separate GCC 16.2.0 build also passed static ABI checks;
see `docs/gcc-16.2.0-compatibility-6.18.43.md`. These are compile-time and
static checks only, not a guarantee of SR-IOV stability on every Intel GPU.
