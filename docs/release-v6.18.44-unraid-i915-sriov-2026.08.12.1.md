# Unraid 7.3.2 / Linux 6.18.44 / i915 SR-IOV 2026.08.12.1

本发布基于官方 Unraid 7.3.2 USB 包，使用来自 `ich777/unraid_kernel` 的
`6.18.44-Unraid` 构建（2026-08-12 发布，上游用 GCC 14.2.0 预编译；
此处用 GCC 15.3.0 重新编译）。

包含的内核相关组件：

- 使用 6.18.44 Unraid 配置编译的全部 1,197 个内核树内模块
- strongtz i915 SR-IOV `2026.08.12.1`（`i915`、`intel_sriov_compat`、
  `kvmgt`、`xe`）—— 6.17.x ~ 7.1.x 驱动分支的最新发布，持续适配 6.18
  系列小版本（PR #473）
- OpenZFS 2.4.3（`spl`、`zfs`），与 Unraid 7.3.2 用户空间匹配
- 兼容 giganode 插件的 `i915-sriov-202608121-6.18.44-Unraid-1.txz`

发布构建使用 GCC 15.3.0。内核模块采用 XZ + CRC32 压缩，这是 6.18.44
模块解压器所要求的格式。

## 校验和

```text
85f4df8687a1948ecc0c5153ba71b17f6e023e517964e97e9ad0177cbac2fec0  unRAIDServer-7.3.2-Linux-6.18.44-i915-sriov-2026.08.12.1-x86_64.zip
044e6f19e985489c7e69955d5c94062427984af3ceebba4b1fe0638f24a5faf7  i915-sriov-202608121-6.18.44-Unraid-1.txz
db19854339b7052d98cd08bd26d81c060c62586ccbb2e0be9777684c85eed071  bzimage-6.18.44-Unraid
4834cd8f6da03aaae81bb2ec1f8b5fa9ccbe0b0c427faa82a872e7b8041977dc  bzroot-6.18.44-Unraid
01811f5fe1d2214928f24a398109ab10bd2a995454a81a040ce7c86dd1cd6ebb  bzmodules（与官方 Unraid 7.3.2 完全一致）
```

## 安装

使用完整 ZIP，把 `bzimage` 和 `bzroot` 一起替换；`bzmodules` 保持官方
Unraid 7.3.2 不变。确保默认 syslinux 启动项包含：

```text
intel_iommu=on i915.enable_guc=3 i915.max_vfs=7 module_blacklist=xe
```

对于已安装 6.18.44-Unraid 的系统，在 i915 未加载时安装插件包：

```sh
sha256sum -c i915-sriov-202608121-6.18.44-Unraid-1.txz.sha256
upgradepkg --install-new i915-sriov-202608121-6.18.44-Unraid-1.txz
depmod -a 6.18.44-Unraid
```

重启后验证：

```sh
uname -r
modinfo i915 | egrep '^(version|vermagic|origin_kernel):'
```

## 验证

静态验证全部通过：

- 内核和所有自定义模块报告 `GCC: (GNU) 15.3.0`；
- i915 版本 `2026.08.12.1-sriov`，vermagic 为 `6.18.44-Unraid SMP preempt
  mod_unload`；
- i915、compat、kvmgt、xe、spl、zfs 全部使用 XZ CRC32；
- 对 1,197 个暂存模块执行 `depmod -e` 无未解析符号；
- 完整 ZIP 通过 `unzip -t` 检查，`bzmodules` 与官方 Unraid 7.3.2 镜像
  逐字节一致。

以上只是编译期和静态 ABI 检查，并不能保证在所有 Intel GPU 上 SR-IOV 的
稳定性。测试前请保留原始 USB 文件和恢复启动项。
