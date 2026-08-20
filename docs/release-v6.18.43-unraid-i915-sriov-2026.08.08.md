# Unraid 7.3.2 / Linux 6.18.43 / i915 SR-IOV 2026.08.08

本测试发布基于官方 Unraid 7.3.2 USB 包，使用来自 `ich777/unraid_kernel`
的 `6.18.43-Unraid` 构建。

包含的内核相关组件：

- 使用 6.18.43 Unraid 配置编译的全部 1,194 个内核树内模块
- strongtz i915 SR-IOV 2026.08.08（`i915`、`intel_sriov_compat`、
  `kvmgt`、`xe`）
- OpenZFS 2.4.3（`spl`、`zfs`），与 Unraid 7.3.2 用户空间匹配
- 兼容 giganode 插件的 `i915-sriov-20260808-6.18.43-Unraid-1.txz`

发布构建使用 GCC 15.3.0。另有一个 GCC 16.2.0 的完整内核和外部模块兼容
性构建也通过了静态 ABI 检查，记录在
`docs/gcc-16.2.0-compatibility-6.18.43.md`，不掺入本发布 ZIP。

使用完整 zip。它把 `bzimage` 和 `bzroot` 一起替换，保留官方 `bzmodules`、
`bzfirmware`、引导加载程序和配置骨架。已有插件用户应在重启前把缓存的
6.18.43 驱动包替换为随包提供的 20260808 版本。

建议的启动参数：

```text
intel_iommu=on i915.enable_guc=3 i915.max_vfs=7 module_blacklist=xe
```

测试前请保留原始 `bzimage` 和 `bzroot` 的可恢复副本。这是实验性的驱动
移植，尚未在所有支持的 Intel 平台上做过启动测试。
