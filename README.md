# Unraid 内核自动构建

本仓库实现 Unraid 内核的自动重建与发布：每日检测官方 Unraid 与
[ich777/unraid_kernel](https://github.com/ich777/unraid_kernel) 上游更新，
有更新即自动触发 GitHub 云编译并发布 Release，全程无需本地编译。

> i915 SR-IOV 驱动已单独提取为插件包，本仓库不再构建或追踪它。

## 最新发布

当前组合：**Unraid 7.4.0-beta.1 / Linux 6.18.44-Unraid**

→ [GitHub Releases](https://github.com/hellomrli/my-unraid-kernel/releases)

| 产物 | 用途 |
| --- | --- |
| `unRAIDServer-...-x86_64.zip` | 完整 USB 安装包，替换官方包中的 `bzimage` 与 `bzroot`，其余文件原样保留 |
| `bzimage-<KERNEL>` / `bzroot-<KERNEL>` | 用官方 GCC 工具链从源码重建的内核与模块树 |
| `sha256sums-<KERNEL>.txt` | 上述产物的 SHA-256 校验和 |
| `verification-<KERNEL>.txt` | 静态验证报告（vermagic、编译器、ZFS 版本、模块数等） |

## 快速使用

替换 Unraid USB 中的 `bzimage` 与 `bzroot`（`bzmodules` 等保持官方原样），
然后按官方方式启动：

```sh
sha256sum -c sha256sums-6.18.44-Unraid.txt
# 将 bzimage-6.18.44-Unraid 覆盖为 bzimage，bzroot-6.18.44-Unraid 覆盖为 bzroot
```

**验证**：

```sh
uname -r
modinfo zfs | egrep '^(version|vermagic):'
```

## 自动构建机制

每日 02:30 UTC，`Watch upstream releases` 工作流检测两个上游源：

1. **Unraid 官方**：`releases.unraid.net/json`（最新公开版本，含 beta/rc），
   并从官方 `bzimage` 提取内核版本与 GCC 版本（`extract-official-gcc.py`）
2. **ich777/unraid_kernel**：最新 GitHub Release（内核源码包信号），
   以及构建实际消费的官方内核源码包的校验和

任一源有更新且原料齐备（官方 zip 可下载、官方内核/GCC 可提取、ich777
已发布对应内核源码包）时，自动以 `auto-latest` 目标触发云编译。构建成功
即发布 Release 并回写状态文件（`config/upstream-state.env`）；失败则状态
不变，次日重试。已运行/排队中的构建不会重复触发。

**设计原则**：

- **GCC 以官方为准**：容器镜像版本取 `max(15.3.0, 官方内核 GCC)`，官方升级即自动跟随
- **完整重建**：用官方 GCC 从源码重建内核（bzImage + 全部树内模块）与
  OpenZFS，再打包为完整 USB 镜像
- **全自动发布**：Release 标签 `v<UNRAID>-<KERNEL>` 不存在时自动创建

手动触发：Actions 页运行 `Watch upstream releases`（日志会显示检测结果与
是否派发构建），或直接运行 `Build Unraid packages` 选择目标。

## 本地构建（可选）

云编译之外的调试手段，命令与配置说明见 `config/*.env`（注释均为中文）：

```bash
scripts/all.sh                    # 默认配置（build.env）
BUILD_ENV_FILE=config/build-6.18.44.env scripts/all.sh
```

## 验证与限制

每个发布在上传前均通过静态验证（`scripts/50-verify.sh`）：模块 vermagic、
编译器标记、`depmod -e` 无未解析符号、ZIP 完整性、bzmodules 逐字节一致性。

以上为编译期与静态 ABI 检查，**不保证**运行时稳定性。测试前请备份原 USB
文件并保留恢复启动项。
