# Unraid 7.3.2 / Linux 6.18.43 / GCC 16.2.0 兼容性发布

本发布用 GCC 16.2.0 重新构建 6.18.43-Unraid 系统包，包含：

- 面向 Intel Alder Lake SR-IOV 的 strongtz i915 SR-IOV 2026.08.08；
- 与 Unraid 7.3.2 用户空间匹配的 OpenZFS 2.4.3 模块；
- 采用 XZ + CRC32 压缩的内核模块，这是 6.18.43 内核模块解压器所要求
  的格式；
- 驱动包修订号 `i915-sriov-20260808-6.18.43-Unraid-2.txz`。

静态验证全部通过：

- 内核和全部六个自定义模块报告 `GCC: (GNU) 16.2.0`；
- i915、compat、kvmgt、xe、spl、zfs 全部使用 XZ CRC32；
- 所有自定义模块 vermagic 为 `6.18.43-Unraid SMP preempt mod_unload`；
- 对 1,197 个暂存模块执行 `depmod -e` 无未解析符号；
- 完整 ZIP 通过 `unzip -t` 检查，并逐字节保留官方 Unraid 7.3.2 的
  `bzmodules` 镜像。

SHA-256：

```text
755ea2c8e9dd4cba543d61f2458bf20e085c5f0034860707e43ddf654bf39df6  unRAIDServer-7.3.2-Linux-6.18.43-i915-sriov-2026.08.08-x86_64.zip
00b5abfcf6e934f7be589fc123d0f3f7630d0ea0f2f38f98bfa4f0f278592fef  i915-sriov-20260808-6.18.43-Unraid-2.txz
```

之前的包对手动压缩的模块使用了用户空间 `xz` 默认的 CRC64。本构建的内核
只接受 XZ none/CRC32 校验，导致 i915 和 ZFS 都报 `decompression failed with
status 6`（解压失败，状态 6）。

使用完整 ZIP 把 `bzimage` 和 `bzroot` 一起替换。重启前确保默认 syslinux
启动项包含：

```text
intel_iommu=on i915.enable_guc=3 i915.max_vfs=7 module_blacklist=xe
```

如果 `/boot/config/modprobe.d/i915.conf` 仍包含 `blacklist i915`，请在启动
`emhttp` 之前从 `/boot/config/go` 显式加载模块：

```bash
modprobe i915 enable_guc=3 max_vfs=7
```

重启后、开始工作负载之前，请验证 `Kernel driver in use: i915`、预期的 VF
数量，以及 `zpool status`/`zfs list`。

这是兼容性测试发布，通过了编译期和静态 ABI 验证，但尚未在目标 NAS 上做
启动测试。请保留原始 USB 文件和恢复启动项。
