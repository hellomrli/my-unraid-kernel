# Unraid 7.3.1 完整安装包（Linux 7.1.1 + i915 SR-IOV）

推荐下载：

- `unRAIDServer-7.3.1-Linux-7.1.1-i915-sriov-x86_64.zip`
- `unRAIDServer-7.3.1-Linux-7.1.1-i915-sriov-x86_64.zip.sha256`

这是基于官方 Unraid 7.3.1 zip 的完整 Unraid USB 安装包。它保留官方的
`bzmodules`、`bzfirmware`、`bzroot-gui`、引导加载文件和配置骨架，然后
替换：

- `bzimage` 为 kernel.org Linux `7.1.1`，发布字符串 `7.1.1-Unraid`
- `bzroot` 为重新构建的 initramfs，包含 `/lib/modules/7.1.1-Unraid`

包含的内核模块：

- 移植到 Linux 7.1.1 的 `strongtz/i915-sriov-dkms`
- 针对 `7.1.1-Unraid` 构建的 OpenZFS `2.4.2` `spl.ko.xz` 和 `zfs.ko.xz`

建议的 syslinux 启动参数：

```text
intel_iommu=on i915.enable_guc=3 i915.max_vfs=7 module_blacklist=xe
```

SHA256：

```text
249491380d5c424a93b87240de51f20dddd175b7db090502e9965245d54b35a5  unRAIDServer-7.3.1-Linux-7.1.1-i915-sriov-x86_64.zip
0672d18e7a93dbb4222a5bd2ee94f15043ca535cc165e7337044329f4a269b4e  bzimage
97d0ffded19a63d5feb0def2b40a3c398c3cb33877d0ea1d5e7570644d419db5  bzroot
```

单独的 `bzimage`、配置、补丁和模块清单资产只作为构建产物保留。测试时请
使用上面的完整 zip。

这是实验性的向前移植。构建成功并不保证运行时稳定。
