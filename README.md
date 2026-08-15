# Unraid i915 SR-IOV kernel builds

This repository publishes experimental Unraid kernels and i915 SR-IOV
packages. The default `main` branch contains the current 6.18 build. Build
inputs and verification notes are kept alongside the scripts and release
documents.

## Branches

| Branch | Contents |
| --- | --- |
| `main` | Unraid 7.3.2 with Linux `6.18.44-Unraid`, i915 SR-IOV `2026.08.12.1`, and OpenZFS 2.4.3. |
| `7.0` | The previous history: the Unraid 7.3.1 / Linux 7.1.1 build. |

The `main` build is available from the GitHub Releases page. The release
assets include:

- `unRAIDServer-7.3.2-Linux-6.18.44-i915-sriov-2026.08.12.1-x86_64.zip`: a
  complete Unraid USB package, including the rebuilt `bzimage` and `bzroot`.
- `i915-sriov-202608121-6.18.44-Unraid-1.txz`: the plugin-compatible driver
  package for an existing 6.18.44-Unraid installation.
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
out/unRAIDServer-7.3.2-Linux-6.18.44-i915-sriov-2026.08.12.1-x86_64.zip
out/i915-sriov-202608121-6.18.44-Unraid-1.txz
```

To build only the driver package for stock Unraid 7.3.2 / 6.18.38-Unraid:

```bash
BUILD_ENV_FILE=config/build-6.18.38-plugin.env scripts/all.sh
```

That mode uses the matching prebuilt kernel ABI and produces
`out/i915-sriov-20260808-6.18.38-Unraid-1.txz`.

For the GCC 16.2.0 compatibility build used by the 2026-08-12 test release:

```bash
tool_root=/home/lain/codex/i915/.toolchains/host-tools
PATH="$tool_root/usr/bin:$PATH" \
BISON_PKGDATADIR="$tool_root/usr/share/bison" \
HOSTCFLAGS="-I$tool_root/usr/include" \
HOSTLDFLAGS="-L/usr/lib/x86_64-linux-gnu -L$tool_root/usr/lib/x86_64-linux-gnu" \
BUILD_ENV_FILE=config/build-gcc-16.2.0.env scripts/all.sh
```

This produces the full 6.18.43 package and the revision-2 driver package
`out/i915-sriov-20260808-6.18.43-Unraid-2.txz`.

## GitHub Actions

Builds can run on GitHub-hosted runners from the **Actions** tab using the
`Build Unraid packages` workflow. Choose `full-6.18.44` for the complete USB
package, `full-6.18.43` for the previous release configuration, or
`plugin-6.18.38` for the stock-kernel driver package. The workflow
uses the official GCC 15.3.0 container, verifies all generated checksums, and
keeps the outputs as a 14-day Actions artifact. Enable `publish_release` and
provide an existing release tag when the outputs should also be attached to a
Release. A full build is CPU-, disk-, and network-intensive and can take
several hours.

## Boot and install

Use the i915 path and keep `xe` blacklisted:

```text
intel_iommu=on i915.enable_guc=3 i915.max_vfs=7 module_blacklist=xe
```

For the plugin package, verify the checksum and install it while i915 is not
loaded:

```sh
sha256sum -c i915-sriov-202608121-6.18.44-Unraid-1.txz.sha256
upgradepkg --install-new i915-sriov-202608121-6.18.44-Unraid-1.txz
depmod -a 6.18.44-Unraid
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

The published 6.18.44 release passed module vermagic, compiler-marker, and
`depmod -e` checks. These are compile-time and static checks only, not a
guarantee of SR-IOV stability on every Intel GPU.
