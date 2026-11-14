# my-unraid-kernel

以官方 Unraid 系统包为基础，自动构建 ich777 的较新内核和匹配模块，再发布可校验的 USB 安装包。

[下载发布包](https://github.com/hellomrli/my-unraid-kernel/releases) · [安装与回退](docs/install.md) · [构建指南](docs/building.md) · [文档索引](docs/index.md)

> [!IMPORTANT]
> 这是社区内核构建。选择与你计划使用的 Unraid 基础版本对应的完整包，备份 U 盘并保留恢复启动项；静态校验不等于运行时稳定性验证。

## 选择发布包

打开 Releases，核对标签中的 Unraid 版本和完整内核版本。不要将不同基础版本的 `bzroot` 与现有官方用户空间混用。

在现有 Unraid 中可先查看：

```sh
cat /etc/unraid-version
uname -r
```

优先使用完整的 `unRAIDServer-...-Linux-...-x86_64.zip`，其中已包含配套 `bzimage`、`bzroot` 和 `.sha256`。手工替换与升级步骤见[安装指南](docs/install.md)。

| 产物 | 用途 |
|---|---|
| `unRAIDServer-...-x86_64.zip` 与 `.zip.sha256` | 完整 USB 文件布局及下载校验 |
| `bzimage-内核`、`bzroot-内核` | 替换内核与对应模块树 |
| `bzimage.sha256`、`bzroot.sha256` | Unraid 启动检查需要的裸哈希旁路文件 |
| `sha256sums-内核.txt` | 内核、bzroot、官方 bzmodules 与完整包的校验清单 |
| `verification-内核.txt` | 编译器、模块 ABI、ZFS 等静态验收记录 |

当前版本以 Releases 为准。旧的 i915 集成发布说明保存在[历史文档](docs/index.md)；现在 Intel SR-IOV 驱动由[独立驱动仓库](https://github.com/hellomrli/my-i915-sriov-driver)发布。

## 自动构建做什么

- 每天 UTC 02:30 检查官方 Unraid 最新公开版本与 ich777 最新内核。
- 以官方 USB 包提供用户空间、固件和 `bzmodules`，替换 `bzimage` 和 `bzroot` 中的内核模块树。
- 从官方内核提取 GCC 版本，云构建使用至少 15.3.0 的匹配工具链。
- 为新内核重建 OpenZFS，并在上传前检查模块 vermagic、未解析符号、ZIP 完整性和官方 `bzmodules` 一致性。
- 只有构建成功才更新上游状态；失败后等待下一次检查重试。

机制和树外模块头文件限制见[构建原理](docs/design.md)。

## 手动构建与反馈

在 Actions 中运行“Watch upstream releases”检查上游，或“Build Unraid packages”选择目标。已有本地配方也可用于复现，步骤见[构建指南](docs/building.md)。

提交 [Issue](https://github.com/hellomrli/my-unraid-kernel/issues) 时提供基础 Unraid 版本、完整内核、使用的 Release、启动错误和相关模块日志。本仓库目前没有根目录许可证文件；Unraid、Linux、OpenZFS 和上游组件沿用各自授权。
