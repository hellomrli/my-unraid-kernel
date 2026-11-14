# 构建 Unraid 内核包

本页用于维护 Actions 或复现内核构建。默认使用云构建，主机上不需要安装完整工具链。

## 触发上游检查

在 Actions 运行 [Watch upstream releases](../.github/workflows/watch-upstream.yml)。它读取官方 `releases.unraid.net/json` 与 ich777 最新 Release，比较 [upstream-state.env](../config/upstream-state.env)，原料可用且有更新时派发 `auto-latest` 构建。

状态只有成功发布后才前进。已有运行或排队的云构建时跳过重复派发；检测失败时从日志核对官方 ZIP、GCC 提取和内核源码归档。

## 手动选择构建

[Build Unraid packages](../.github/workflows/build.yml) 提供 `auto-latest` 和已有固定配方。固定配方用于复现历史组合，不代表当前最新版本。

自动目标的 `auto_params` 指定官方版本、ZIP、内核归档、校验和和 GCC 信息。开启 `publish_release` 时必须提供 `release_tag`；发布前检查目标组合和静态验收结果。

云构建使用 `max(15.3.0, 官方内核 GCC)`，工具链以实际工作流和官方提取值为准。

## 本地复现

准备 Linux 开发环境和 [00-check-env.sh](../scripts/00-check-env.sh) 要求的工具、编译器与 ZFS 开发依赖。在克隆目录选择已有环境文件：

```bash
git clone https://github.com/hellomrli/my-unraid-kernel.git
cd my-unraid-kernel
BUILD_ENV_FILE=config/build-6.18.44.env scripts/all.sh
```

这是固定配方示例。自己的组合可参照 [build.env.example](../config/build.env.example) 准备新配置，并通过 `BUILD_ENV_FILE` 指向它；内核、官方 Unraid 包、ZFS、GCC 和校验和必须一致。

[all.sh](../scripts/all.sh) 顺序检查环境、下载原料、准备和编译内核、重建 ZFS、打包、验证。该过程需要联网、较大磁盘空间和编译时间，输出目录与并发数由配置控制。

## 检查发布前验收

[50-verify.sh](../scripts/50-verify.sh) 检查内核版本、模块 vermagic、编译器标记、ZFS、未解析符号、ZIP 完整性和官方 `bzmodules` 一致性。成功产物包含 `verification-内核.txt`、校验清单和原料配置记录。

静态验收用于发现构建与 ABI 错误。实际硬件、存储和第三方插件仍需启动后验证，安装步骤见[安装与回退](install.md)。

返回[文档索引](index.md)。
