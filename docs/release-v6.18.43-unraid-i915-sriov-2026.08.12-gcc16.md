# Unraid 7.3.2 / Linux 6.18.43 / GCC 16.2.0 compatibility release

This release rebuilds the 6.18.43-Unraid system package with GCC 16.2.0 and
contains:

- strongtz i915 SR-IOV 2026.08.08 for Intel Alder Lake SR-IOV;
- OpenZFS 2.4.3 modules matching Unraid 7.3.2 userspace;
- XZ-compressed kernel modules using CRC32, which is required by the
  6.18.43 kernel module decompressor;
- driver package revision `i915-sriov-20260808-6.18.43-Unraid-2.txz`.

Static validation completed successfully:

- the kernel and all six custom modules report `GCC: (GNU) 16.2.0`;
- i915, compat, kvmgt, xe, spl, and zfs all use XZ CRC32;
- all custom modules have `6.18.43-Unraid SMP preempt mod_unload` vermagic;
- `depmod -e` reports no unresolved symbols across 1,197 staged modules;
- the complete ZIP passes `unzip -t` and preserves the stock Unraid 7.3.2
  `bzmodules` image byte-for-byte.

SHA-256:

```text
755ea2c8e9dd4cba543d61f2458bf20e085c5f0034860707e43ddf654bf39df6  unRAIDServer-7.3.2-Linux-6.18.43-i915-sriov-2026.08.08-x86_64.zip
00b5abfcf6e934f7be589fc123d0f3f7630d0ea0f2f38f98bfa4f0f278592fef  i915-sriov-20260808-6.18.43-Unraid-2.txz
```

The previous package used the userspace `xz` default CRC64 for the manually
compressed modules. The kernel accepts only XZ none/CRC32 checks in this build,
which caused both i915 and ZFS to fail with `decompression failed with status 6`.

Use the complete ZIP to replace `bzimage` and `bzroot` together. Before reboot,
ensure the default syslinux entry contains:

```text
intel_iommu=on i915.enable_guc=3 i915.max_vfs=7 module_blacklist=xe
```

If `/boot/config/modprobe.d/i915.conf` still contains `blacklist i915`, load
the module explicitly from `/boot/config/go` before starting `emhttp`:

```bash
modprobe i915 enable_guc=3 max_vfs=7
```

After reboot, verify `Kernel driver in use: i915`, the expected VF count, and
`zpool status`/`zfs list` before starting workloads.

This is a compatibility test release. It passed compile-time and static ABI
validation but has not yet been boot-tested on the target NAS. Keep the
original USB files and a recovery boot entry available.
