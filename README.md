# Unraid i915 SR-IOV 内核构建

本仓库发布实验性的 Unraid 内核与 i915 SR-IOV 驱动包。`main` 分支包含当前
6.18 内核构建。构建输入与验证说明与脚本、发布文档放在一起。

## 分支

| 分支 | 内容 |
| --- | --- |
| `main` | Unraid 7.4.0-beta.1，Linux 内核 `6.18.44-Unraid`，i915 SR-IOV `2026.08.12.1`，沿用测试版的 OpenZFS 2.4.3。 |
| `7.0` | 旧历史：Unraid 7.3.1 / Linux 7.1.1 构建。 |

`main` 分支的构建由**自动云编译**发布到 GitHub Releases 页面。每个发布包含：

- `unRAIDServer-7.4.0-beta.1-Linux-6.18.44-i915-sriov-2026.08.12.1-x86_64.zip`：
  完整 USB 安装包，四个 SR-IOV 模块已合并进其 `bzroot`（官方 `bzimage`、
  `bzmodules`、`bzfirmware`、用户空间和 OpenZFS 模块均原样保留）。
- `i915-sriov-202608121-6.18.44-Unraid-1.txz`：插件驱动包，使用官方内核的
  GCC（15.3.0）编译，适用于已安装 6.18.44-Unraid 内核的系统。
- SHA-256/MD5 校验文件、静态验证报告、`bzimage`、内核配置、模块清单和推荐
  的 syslinux 启动参数。

早前本地构建的 `...-2.txz`（修订号 2）使用 GCC 16.2.0；云编译流程跟随官方
内核的编译器版本，包编号为 `-1`。

## 使用完整 ZIP

替换 Unraid 测试版 USB 内容时使用完整 ZIP。它保留官方测试版的 `bzimage`、
`bzmodules`、`bzfirmware`、引导加载文件、用户空间和 OpenZFS 模块，只把
`bzroot` 替换为合并了 SR-IOV 模块的版本。测试前请备份原始 USB 文件并保留
一个恢复启动项。

## 本地构建

仓库里的 `config/build.env` 固定使用 GCC 16.2.0 编译注入的 SR-IOV 模块
（本地兼容性构建；云编译流程则跟随官方内核的 GCC，目前为 15.3.0）。在本
目录下执行完整构建：

```bash
scripts/all.sh
```

主要产物输出到 `out/`：

```text
out/unRAIDServer-7.4.0-beta.1-Linux-6.18.44-i915-sriov-2026.08.12.1-x86_64.zip
out/i915-sriov-202608121-6.18.44-Unraid-2.txz
```

默认的测试版配置使用官方内核镜像，并把四个 SR-IOV 模块合并进官方模块树，
不重建、不替换测试版中已有的 OpenZFS 模块。

只为官方 Unraid 7.3.2 / 6.18.38-Unraid 构建驱动包：

```bash
BUILD_ENV_FILE=config/build-6.18.38-plugin.env scripts/all.sh
```

该模式使用匹配的预编译内核 ABI，产物为
`out/i915-sriov-20260808-6.18.38-Unraid-1.txz`。

2026-08-12 测试发布使用的 GCC 16.2.0 兼容性构建：

```bash
tool_root=/home/lain/codex/i915/.toolchains/host-tools
PATH="$tool_root/usr/bin:$PATH" \
BISON_PKGDATADIR="$tool_root/usr/share/bison" \
HOSTCFLAGS="-I$tool_root/usr/include" \
HOSTLDFLAGS="-L/usr/lib/x86_64-linux-gnu -L$tool_root/usr/lib/x86_64-linux-gnu" \
BUILD_ENV_FILE=config/build-gcc-16.2.0.env scripts/all.sh
```

这会生成完整的 6.18.43 安装包和修订号 2 的驱动包
`out/i915-sriov-20260808-6.18.43-Unraid-2.txz`。

## GitHub Actions（云编译）

### 云编译（不在本地编译）

所有编译都在 GitHub 托管的运行器上、官方 GCC 容器镜像内完成。编译器版本
**以 Unraid 官方内核包为准**：构建时通过 `scripts/extract-official-gcc.py`
读取官方 `bzimage` 中嵌入的 GCC 版本，取 `max(15.3.0, 官方 GCC)` 作为容器
镜像标签。手动目标也按同样方式解析；显式传入 `gcc_version` 输入参数时以
该参数为准。

提供两个工作流：

- **Build Unraid packages**（`build.yml`）—— 构建手动目标
  （`full-7.4.0-beta.1`、`full-6.18.44`、`full-6.18.43`、`plugin-6.18.38`），
  或 `auto-latest` 全参数化构建。启用 `publish_release` 并提供
  `release_tag` 时，产物会附加到 Release；如果标签不存在会自动创建。产物
  同时以 14 天为期的 Actions 工件保留。完整构建非常消耗 CPU、磁盘和网络，
  可能耗时数小时。
- **Watch upstream releases**（`watch-upstream.yml`）—— 每天（UTC 02:30，
  也可手动触发或通过 `repository_dispatch` 类型 `check-upstream` 触发）
  检查三个上游来源：
  1. 官方 Unraid 版本 JSON（`releases.unraid.net/json`，取最新的公开版本，
     含 beta/rc）；
  2. 官方 `bzimage` 中的内核版本 + GCC 版本；
  3. 最新的 `strongtz/i915-sriov-dkms` 标签。

  `scripts/detect-upstream.sh` 汇总三个来源的当前状态；
  `scripts/upstream-compare.py` 与 `config/upstream-state.env`（上次成功构建
  的组合）比较。当任一来源有更新、且所有原料都齐备（ich777 已为官方内核
  发布内核源码包、i915 提交已固定）时，watch 工作流以 `target=auto-latest`
  触发 `build.yml`，并传入计算好的发布标签 `v<UNRAID>-<KERNEL>-i915-<REF>`
  和解析出的 GCC 版本。

自动构建使用**官方集成模式**：原样使用官方 `bzimage`、`bzmodules`、用户
空间和 OpenZFS 模块（`USE_STOCK_BZIMAGE=true`、`MERGE_STOCK_MODULES=true`、
`USE_STOCK_ZFS=true`、`REBUILD_KERNEL=false`），只把 `bzroot` 替换为合并了
四个 SR-IOV 模块的版本。自动构建成功后，工作流会更新
`config/upstream-state.env` 并推送，因此下次运行在任一路上游源更新之前都
是空操作。构建失败则状态保持不变，下一次每日运行会重试。

手动触发检查：在 Actions 页运行 `Watch upstream releases`，日志会显示检测
到的版本、上次构建的状态以及是否派发了云编译。

### 端到端验证

2026-08-20 用一次真实的云编译验证了整条流程：watch 参数解析出 GCC 15.3.0，
构建在 `gcc:15.3.0` 容器内运行，并发布了
[release `v7.4.0-beta.1-6.18.44-Unraid-i915-2026.08.12.1`](https://github.com/hellomrli/my-unraid-kernel/releases/tag/v7.4.0-beta.1-6.18.44-Unraid-i915-2026.08.12.1)，
包含 1.2 GB 的 USB ZIP、插件 `.txz`、校验文件和验证报告。上游状态文件随后
已同步更新到 `main`。

技术说明：bzroot 解包使用 `scripts/unpack-bzroot.py`（仅标准库）。Debian
系 GCC 容器镜像自带的 `unmkinitramfs` 无法处理官方 Unraid bzroot 的格式
（未压缩 `newc` cpio + `zstd` 压缩 cpio 拼接），因此流程直接改用 GNU
`cpio` 解包。

## 启动与安装

使用 i915 直通并屏蔽 `xe`：

```text
intel_iommu=on i915.enable_guc=3 i915.max_vfs=7 module_blacklist=xe
```

插件包在 i915 未加载时校验并安装（修订号以发布为准，当前云编译为 `-1`）：

```sh
sha256sum -c i915-sriov-202608121-6.18.44-Unraid-1.txz.sha256
upgradepkg --install-new i915-sriov-202608121-6.18.44-Unraid-1.txz
depmod -a 6.18.44-Unraid
```

重启进入对应内核后检查：

```sh
uname -r
modinfo i915 | egrep '^(version|vermagic|origin_kernel):'
```

不要在有活跃控制台时卸载 i915，也不要将物理功能 GPU 直通给虚拟机。如果
初始化失败，用 `module_blacklist=i915,xe` 进入恢复启动项。

## 验证

每个发布的版本都通过模块 vermagic、编译器标记和 `depmod -e` 检查，本地
构建和云编译流程都会执行——`scripts/50-verify.sh` 会先解包重打包后的
`bzroot` 并验证，之后才上传。这些只是编译期和静态检查，并不能保证在所有
Intel GPU 上 SR-IOV 的稳定性。
