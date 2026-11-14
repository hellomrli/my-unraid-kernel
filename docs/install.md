# 安装与回退社区内核

本页用于在 Unraid U 盘上使用本仓库的发布包。开始前备份完整 U 盘，保留现有 `config/` 和可启动的恢复文件；确认发布包的基础 Unraid 版本与计划使用的系统一致。

## 使用完整 USB 包

1. 从 [Releases](https://github.com/hellomrli/my-unraid-kernel/releases) 下载所选 `unRAIDServer-...zip` 和同名 `.zip.sha256`。
2. 在下载目录校验该 ZIP，并检查压缩包完整性。
3. 按所选 Unraid 版本的 USB 更新流程使用完整布局，保留自己的 `config/`。
4. 重启后检查完整内核和 ZFS 模块。

校验命令中的文件名使用你下载的实际名称，例如：

```sh
sha256sum -c unRAIDServer-7.4.0-Linux-6.18.60-x86_64.zip.sha256
unzip -t unRAIDServer-7.4.0-Linux-6.18.60-x86_64.zip
```

示例只说明命名和检查方式，不将该版本固定为今后的最新选择。完整包已生成正确的 `bzimage.sha256`、`bzroot.sha256`。

## 手工替换两份引导文件

仅在官方基础版本和其余 USB 文件一致时进行。下载同一 Release 的 `bzimage-内核`、`bzroot-内核`、`bzimage.sha256`、`bzroot.sha256`。

1. 将现有 `bzimage`、`bzroot` 及各自 `.sha256` 一起备份。恢复启动项中的备份文件也需要同名旁路哈希。
2. 将下载的内核文件改名为 `/boot/bzimage`，对应模块映像改名为 `/boot/bzroot`。
3. 同步复制该 Release 的两份 `.sha256`。
4. 保留同一官方基础包的 `bzmodules`、`bzfirmware` 和 `bzroot-gui`。

Unraid 启动时使用裸 SHA256 旁路文件检查引导文件。缺失或不匹配会中止启动，不能只替换内核而保留旧哈希。

`sha256sums-内核.txt` 同时包含官方 `bzmodules` 和完整 ZIP；校验整份清单需准备所有列出的文件。不要把仅下载两个内核文件时的“缺少 bzmodules”误判为它们损坏。

## 重启后验证

在 Unraid 中运行：

```sh
uname -r
modinfo zfs | sed -n '/^version:/p; /^vermagic:/p'
```

确认内核和模块版本符合所选 Release，再检查实际存储与设备工作负载。编译期检查不覆盖全部硬件的运行时行为。

## 恢复原内核

恢复原 `bzimage`、`bzroot` 和对应 `.sha256`，或使用准备好的恢复启动项。若切换了基础 Unraid 版本，其余官方文件也应恢复到同一版本。

原项目记录的 `/boot/config/skipbzcheck` 是跳过启动校验的救急开关；正常安装应修复文件与哈希的一致性，而不是依赖它完成更新。

树外驱动编译缺少头文件时，查看[构建原理](design.md)。返回[文档索引](index.md)。
