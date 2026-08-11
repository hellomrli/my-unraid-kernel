# GCC 16.2.0 Compatibility Test

This is the GCC 16.2.0 compatibility release for the 6.18.43-Unraid ABI. The
release notes and package details are in
`docs/release-v6.18.43-unraid-i915-sriov-2026.08.12-gcc16.md`.

## Toolchain

- GCC source: `gcc-16.2.0.tar.xz`
- SHA-512: `c51c30ca7422d0cbecf504b2e0f33c3aca31e0f90a76b65217f465163fa6fa17b3f5de39e145c47e5bab90ac0ce7fff3b03c8d553ae36e01faaea5a50f8648d1`
- Configuration: C language only, no bootstrap, no multilib, no LTO
- GCC 16's `libatomic` target was built and installed for host-tool linking

## Results

The complete `6.18.43-Unraid` kernel configuration built successfully with
GCC 16.2.0, including `bzImage`, all 1,197 staged in-tree modules and MODPOST.

The following external modules also built successfully against that ABI:

```text
strongtz i915 SR-IOV 2026.08.08: i915, intel_sriov_compat, kvmgt, xe
OpenZFS 2.4.3: spl, zfs
```

All six modules reported `6.18.43-Unraid SMP preempt mod_unload` vermagic and
the ELF `.comment` string `GCC: (GNU) 16.2.0`. `depmod -e` reported no
unresolved symbols and resolved `i915` to the SR-IOV module path. The raw
verification output is in `out/depmod-gcc-16.2.0-6.18.43.txt`; build logs are
`logs/build-kernel-gcc-16.2.0.log`, `logs/build-i915-gcc-16.2.0.log` and
`logs/build-zfs-gcc-16.2.0.log`.

This proves compilation and static ABI compatibility only. The package has not
been boot-tested on the target Unraid host; reboot only after keeping a
recovery boot entry and backing up the original USB files.
