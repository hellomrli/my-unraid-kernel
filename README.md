# Unraid i915 SR-IOV 自动构建

本仓库实现 Unraid 内核的 i915 SR-IOV 驱动自动构建与发布：每日检测上游更新，
有更新即自动触发 GitHub 云编译并发布 Release，全程无需本地编译。

## 最新发布

当前组合：**Unraid 7.4.0-beta.1 / Linux 6.18.44-Unraid / i915 SR-IOV 2026.08.12.1**
（GCC 15.3.0，与官方内核编译器一致）

→ [GitHub Releases](https://github.com/hellomrli/my-unraid-kernel/releases)

| 产物 | 用途 |
| --- | --- |
| `unRAIDServer-...-x86_64.zip`（约 1.2 GB） | 完整 USB 安装包，替换官方包中的 `bzroot`（合并 SR-IOV 模块），其余文件原样保留 |
| `i915-sriov-...-Unraid-1.txz` | 插件驱动包，适用于已安装对应内核的系统 |

## 快速使用

**完整包**：替换 Unraid USB 中的 `bzimage` 与 `bzroot`（`bzmodules` 等保持官方原样），
syslinux 启动参数加入：

```text
intel_iommu=on i915.enable_guc=3 i915.max_vfs=7 module_blacklist=xe
```

**插件包**：i915 未加载时安装，重启生效：

```sh
sha256sum -c i915-sriov-202608121-6.18.44-Unraid-1.txz.sha256
upgradepkg --install-new i915-sriov-202608121-6.18.44-Unraid-1.txz
depmod -a 6.18.44-Unraid
```

**验证**：

```sh
uname -r
modinfo i915 | egrep '^(version|vermagic|origin_kernel):'
```

> 注意：不要在有活跃控制台时卸载 i915；初始化失败时用
> `module_blacklist=i915,xe` 进入恢复启动项。

## 自动构建机制

每日 02:30 UTC，`Watch upstream releases` 工作流检查三个上游源：

1. **Unraid 官方**：`releases.unraid.net/json`（最新公开版本，含 beta/rc）
2. **官方内核**：从官方 bzimage 提取内核版本与 GCC 版本（`extract-official-gcc.py`）
3. **i915 驱动**：`strongtz/i915-sriov-dkms` 最新标签

任一源有更新且原料齐备（ich777 已发布对应内核源码包）时，自动以
`auto-latest` 目标触发云编译。构建成功即发布 Release 并回写状态文件
（`config/upstream-state.env`）；失败则状态不变，次日重试。已运行/排队中
的构建不会重复触发。

**设计原则**：

- **GCC 以官方为准**：容器镜像版本取 `max(15.3.0, 官方内核 GCC)`，官方升级即自动跟随
- **官方集成模式**：原样使用官方 bzimage/用户空间/OpenZFS，只把四个 SR-IOV
  模块（i915、kvmgt、xe、intel_sriov_compat）合并进 bzroot
- **全自动发布**：Release 标签 `v<UNRAID>-<KERNEL>-i915-<REF>` 不存在时自动创建

手动触发：Actions 页运行 `Watch upstream releases`（日志会显示检测结果与
是否派发构建），或直接运行 `Build Unraid packages` 选择目标。

## 本地构建（可选）

云编译之外的调试手段，命令与配置说明见 `docs/` 与 `config/*.env`（注释均为中文）：

```bash
scripts/all.sh                    # 默认配置（build.env）
BUILD_ENV_FILE=config/build-6.18.38-plugin.env scripts/all.sh   # 纯插件包
```

## 验证与限制

每个发布在上传前均通过静态验证（`scripts/50-verify.sh`）：模块 vermagic、
编译器标记、`depmod -e` 无未解析符号、ZIP 完整性、bzmodules 逐字节一致性。

以上为编译期与静态 ABI 检查，**不保证** SR-IOV 在所有 Intel GPU 上的运行时
稳定性。测试前请备份原 USB 文件并保留恢复启动项。

## 历史发布记录

`docs/` 下按版本归档，含各版本校验和与构建说明（中文）：
`release-v7.4.0-beta.1`、`release-v6.18.44`、`release-v6.18.43`（×2，含
GCC 16.2.0 兼容版）、`release-v6.18.38`、`release-v7.1.1`、`gcc-16.2.0-compatibility-6.18.43`。
