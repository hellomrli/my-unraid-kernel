# GCC 16.2.0 兼容性测试

这是针对 6.18.43-Unraid ABI 的 GCC 16.2.0 兼容性发布。发布说明和包详情见
`docs/release-v6.18.43-unraid-i915-sriov-2026.08.12-gcc16.md`。

## 工具链

- GCC 源码：`gcc-16.2.0.tar.xz`
- SHA-512：`c51c30ca7422d0cbecf504b2e0f33c3aca31e0f90a76b65217f465163fa6fa17b3f5de39e145c47e5bab90ac0ce7fff3b03c8d553ae36e01faaea5a50f8648d1`
- 配置：仅 C 语言，无 bootstrap，无 multilib，无 LTO
- 为宿主工具链链接构建并安装了 GCC 16 的 `libatomic` 目标

## 结果

完整的 `6.18.43-Unraid` 内核配置用 GCC 16.2.0 构建成功，包括 `bzImage`、
全部 1,197 个暂存内核树内模块和 MODPOST。

以下外部模块也针对该 ABI 构建成功：

```text
strongtz i915 SR-IOV 2026.08.08: i915, intel_sriov_compat, kvmgt, xe
OpenZFS 2.4.3: spl, zfs
```

六个模块都报告 vermagic `6.18.43-Unraid SMP preempt mod_unload` 和 ELF
`.comment` 字符串 `GCC: (GNU) 16.2.0`。`depmod -e` 无未解析符号，
`i915` 解析到 SR-IOV 模块路径。原始验证输出在
`out/depmod-gcc-16.2.0-6.18.43.txt`；构建日志为
`logs/build-kernel-gcc-16.2.0.log`、`logs/build-i915-gcc-16.2.0.log` 和
`logs/build-zfs-gcc-16.2.0.log`。

这只能证明编译和静态 ABI 兼容。该包尚未在目标 Unraid 主机上做过启动
测试；请保留恢复启动项并备份原始 USB 文件后再重启。
