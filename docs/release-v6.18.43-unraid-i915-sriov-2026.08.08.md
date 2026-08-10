# Unraid 7.3.2 / Linux 6.18.43 / i915 SR-IOV 2026.08.08

This test release is based on the official Unraid 7.3.2 USB package and uses
the `6.18.43-Unraid` build from `ich777/unraid_kernel`.

Included kernel-specific components:

- all 1,194 in-tree modules built with the 6.18.43 Unraid configuration
- strongtz i915 SR-IOV 2026.08.08 (`i915`, `intel_sriov_compat`, `kvmgt`, `xe`)
- OpenZFS 2.4.3 (`spl`, `zfs`), matching Unraid 7.3.2 userspace
- a giganode-plugin-compatible `i915-sriov-20260808-6.18.43-Unraid-1.txz`

The release build uses GCC 15.3.0. A separate GCC 16.2.0 full-kernel and
external-module compatibility build also passed static ABI checks; it is
recorded in `docs/gcc-16.2.0-compatibility-6.18.43.md` and is not substituted
into this release ZIP.

Use the complete zip. It replaces `bzimage` and `bzroot` together and keeps
the official `bzmodules`, `bzfirmware`, bootloader, and config skeleton.
Existing plugin users should replace the cached 6.18.43 driver package with
the included 20260808 package before rebooting.

Suggested append parameters:

```text
intel_iommu=on i915.enable_guc=3 i915.max_vfs=7 module_blacklist=xe
```

Before testing, keep a recoverable copy of the original `bzimage` and
`bzroot`. This is an experimental driver backport and has not been boot-tested
on every supported Intel platform.
