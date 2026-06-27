# Unraid 7.3.1 custom Linux 7.1.1 kernel with i915 SR-IOV

This workspace builds a custom Unraid boot kernel based on kernel.org Linux
7.1.1 and packages `strongtz/i915-sriov-dkms` modules into `bzmodules`.

The target differs from stock Unraid 7.3.1:

- Unraid 7.3.1 ships `6.18.33-Unraid`.
- kernel.org latest stable is `7.1.1`.
- `strongtz/i915-sriov-dkms` currently advertises support for `6.17.x` through
  `7.0.x`, so building it against `7.1.1` is an experimental forward-port.
- Intel `mainline-tracking/v7.1-rc3` has SR-IOV work in the `xe` driver, but
  does not contain the strongtz i915 SR-IOV implementation.

## Workflow

```bash
cp config/build.env.example config/build.env
scripts/all.sh
```

The generated files are:

- `out/bzimage`
- `out/bzmodules`
- `out/syslinux-append-i915-sriov.txt`

Use the syslinux append line for the i915 path:

```text
intel_iommu=on i915.enable_guc=3 i915.max_vfs=7 module_blacklist=xe
```

## Stages

```bash
scripts/00-check-env.sh
scripts/01-fetch-sources.sh
scripts/10-prepare-kernel.sh
scripts/20-build-kernel.sh
scripts/30-build-i915-sriov.sh
scripts/40-package-unraid.sh
```

`scripts/30-build-i915-sriov.sh` is the expected failure point if Linux 7.1.1
changed DRM/i915 APIs beyond what the current `kernel-v7.0` driver branch
handles. Its log is `logs/build-i915-sriov.log`.

For Linux 7.1.1, this repository includes and automatically applies:

```text
patches/i915-sriov-dkms-linux-7.1.1-forward-port.patch
```

## Notes

Keep backups of the original Unraid USB `bzimage` and `bzmodules` before
replacing them. If boot hangs or display initialization fails, boot once with:

```text
module_blacklist=i915,xe
```

That disables the Intel GPU modules for recovery.
