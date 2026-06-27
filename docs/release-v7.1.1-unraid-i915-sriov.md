# Unraid 7.3.1 full package with Linux 7.1.1 and i915 SR-IOV

Recommended download:

- `unRAIDServer-7.3.1-Linux-7.1.1-i915-sriov-x86_64.zip`
- `unRAIDServer-7.3.1-Linux-7.1.1-i915-sriov-x86_64.zip.sha256`

This is a complete Unraid USB package based on the official Unraid 7.3.1 zip.
It preserves the stock `bzmodules`, `bzfirmware`, `bzroot-gui`, bootloader
files, and config skeleton, then replaces:

- `bzimage` with kernel.org Linux `7.1.1`, release string `7.1.1-Unraid`
- `bzroot` with a rebuilt initramfs containing `/lib/modules/7.1.1-Unraid`

Included kernel modules:

- `strongtz/i915-sriov-dkms` forward-ported to Linux 7.1.1
- OpenZFS `2.4.2` `spl.ko.xz` and `zfs.ko.xz` built against `7.1.1-Unraid`

Suggested syslinux append line:

```text
intel_iommu=on i915.enable_guc=3 i915.max_vfs=7 module_blacklist=xe
```

SHA256:

```text
249491380d5c424a93b87240de51f20dddd175b7db090502e9965245d54b35a5  unRAIDServer-7.3.1-Linux-7.1.1-i915-sriov-x86_64.zip
0672d18e7a93dbb4222a5bd2ee94f15043ca535cc165e7337044329f4a269b4e  bzimage
97d0ffded19a63d5feb0def2b40a3c398c3cb33877d0ea1d5e7570644d419db5  bzroot
```

The standalone `bzimage`, config, patch, and module-list assets are kept only
as build artifacts. Use the full zip above for testing.

This is an experimental forward-port. Build success does not guarantee runtime
stability.
