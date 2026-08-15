# Unraid 7.3.2 / Linux 6.18.44 / i915 SR-IOV 2026.08.12.1

This release is based on the official Unraid 7.3.2 USB package and uses the
`6.18.44-Unraid` build from `ich777/unraid_kernel` (released 2026-08-12,
prebuilt with GCC 14.2.0 upstream; rebuilt here with GCC 15.3.0).

Included kernel-specific components:

- all 1,197 in-tree modules built with the 6.18.44 Unraid configuration
- strongtz i915 SR-IOV `2026.08.12.1` (`i915`, `intel_sriov_compat`, `kvmgt`,
  `xe`) — the latest release of the 6.17.x ~ 7.1.x driver line, which keeps
  building against ongoing 6.18 point releases (PR #473)
- OpenZFS 2.4.3 (`spl`, `zfs`), matching Unraid 7.3.2 userspace
- a giganode-plugin-compatible `i915-sriov-202608121-6.18.44-Unraid-1.txz`

The release build uses GCC 15.3.0. Kernel modules are XZ-compressed with
CRC32, which the 6.18.44 module decompressor requires.

## Checksums

```text
85f4df8687a1948ecc0c5153ba71b17f6e023e517964e97e9ad0177cbac2fec0  unRAIDServer-7.3.2-Linux-6.18.44-i915-sriov-2026.08.12.1-x86_64.zip
044e6f19e985489c7e69955d5c94062427984af3ceebba4b1fe0638f24a5faf7  i915-sriov-202608121-6.18.44-Unraid-1.txz
db19854339b7052d98cd08bd26d81c060c62586ccbb2e0be9777684c85eed071  bzimage-6.18.44-Unraid
4834cd8f6da03aaae81bb2ec1f8b5fa9ccbe0b0c427faa82a872e7b8041977dc  bzroot-6.18.44-Unraid
01811f5fe1d2214928f24a398109ab10bd2a995454a81a040ce7c86dd1cd6ebb  bzmodules (identical to stock Unraid 7.3.2)
```

## Install

Use the complete ZIP and replace `bzimage` and `bzroot` together; `bzmodules`
stays stock Unraid 7.3.2. Ensure the default syslinux entry contains:

```text
intel_iommu=on i915.enable_guc=3 i915.max_vfs=7 module_blacklist=xe
```

For an existing 6.18.44-Unraid installation, install the plugin package while
i915 is not loaded:

```sh
sha256sum -c i915-sriov-202608121-6.18.44-Unraid-1.txz.sha256
upgradepkg --install-new i915-sriov-202608121-6.18.44-Unraid-1.txz
depmod -a 6.18.44-Unraid
```

After reboot, verify:

```sh
uname -r
modinfo i915 | egrep '^(version|vermagic|origin_kernel):'
```

## Validation

Static validation completed successfully:

- the kernel and all custom modules report `GCC: (GNU) 15.3.0`;
- i915 version `2026.08.12.1-sriov` with `6.18.44-Unraid SMP preempt
  mod_unload` vermagic;
- i915, compat, kvmgt, xe, spl, and zfs all use XZ CRC32;
- `depmod -e` reports no unresolved symbols across 1,197 staged modules;
- the complete ZIP passes `unzip -t`, and `bzmodules` is preserved
  byte-for-byte from the official Unraid 7.3.2 image.

These are compile-time and static ABI checks only, not a guarantee of SR-IOV
stability on every Intel GPU. Keep the original USB files and a recovery boot
entry available before testing.
