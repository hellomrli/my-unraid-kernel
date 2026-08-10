# Unraid 7.3.2 Linux 6.18.43 with i915 SR-IOV 2026.08.08

This branch builds a test kernel package for Unraid 7.3.2 using:

- ich777's prebuilt, Unraid-patched `6.18.43-Unraid` kernel tree
- `strongtz/i915-sriov-dkms` tag `2026.08.08`
- OpenZFS `2.4.3`, matching the userspace shipped by Unraid 7.3.2
- the official Unraid 7.3.2 USB zip as the userspace and firmware base

The 6.18.43 kernel is a small patch-level update from the official
`6.18.38-Unraid` kernel. The custom i915 source is based on a newer Intel DRM
tree and needs the included compatibility patch for Unraid's backported slab
allocation helpers.

## Build

```bash
scripts/all.sh
```

The tracked `config/build.env` pins the local GCC 15.3.0 toolchain used for
the release. Use `config/build.env.example` as a template only when moving the
build to another host, and set its compiler paths accordingly.

The main outputs are:

```text
out/unRAIDServer-7.3.2-Linux-6.18.43-i915-sriov-2026.08.08-x86_64.zip
out/i915-sriov-20260808-6.18.43-Unraid-1.txz
```

To build only the driver package for stock Unraid 7.3.2 / 6.18.38-Unraid:

```bash
BUILD_ENV_FILE=config/build-6.18.38-plugin.env scripts/all.sh
```

That mode uses ich777's matching prebuilt tree and `Module.symvers`, builds
the driver with GCC 15.3.0, and produces
`out/i915-sriov-20260808-6.18.38-Unraid-1.txz`. It does not rebuild the stock
kernel or download the full Unraid USB image and OpenZFS sources.

It is a complete USB package. Compared with official Unraid 7.3.2 it replaces
only `bzimage` and `bzroot`. `bzroot` contains the complete
`/lib/modules/6.18.43-Unraid` tree, including:

- all in-tree Unraid kernel modules
- `i915`, `intel_sriov_compat`, `kvmgt`, and `xe` from strongtz 2026.08.08
- OpenZFS 2.4.3 `spl` and `zfs` modules

Unraid 7.3.2 stores kernel modules in `bzroot`; `bzmodules` is its `/usr`
userspace image. Consequently `bzimage` and `bzroot` must always be replaced
together. The full zip preserves the official `bzmodules`, `bzfirmware`,
bootloader files, and configuration skeleton.

## Boot Parameters

Use the i915 path and keep xe blacklisted:

```text
intel_iommu=on i915.enable_guc=3 i915.max_vfs=7 module_blacklist=xe
```

The second output uses the package name and layout expected by
`giganode/unraid-i915-sriov`. Put it in the plugin's `packages/6.18.43`
directory before booting the new kernel, and remove older packages from that
directory. The plugin blacklists and loads i915 itself, so avoid configuring
the same option in several places and do not pass the physical function
through to a VM.

## Recovery

Back up the original USB files before testing. Keep a boot menu entry using
the original `bzimage` and `bzroot`; if GPU initialization prevents booting,
add `module_blacklist=i915,xe` to the recovery entry.

This package is experimental. Successful compilation and static module checks
do not prove SR-IOV stability on a specific Intel GPU.

## Compiler Validation

The published 6.18.43 package is built with GCC 15.3.0. GCC 16.2.0 was also
built locally and used to compile the complete kernel, strongtz i915 SR-IOV
2026.08.08, and OpenZFS 2.4.3 against the same ABI. The six external modules
passed vermagic, compiler-marker, and `depmod -e` checks. See
`docs/gcc-16.2.0-compatibility-6.18.43.md`; this is a static compatibility
result, not a boot-tested release.

The stock 6.18.38 kernel was built by Unraid with GCC 14.2.0. Its plugin-only
2026.08.08 i915 module was intentionally built with GCC 15.3.0 and passed
vermagic and unresolved-symbol checks against the stock kernel ABI.
