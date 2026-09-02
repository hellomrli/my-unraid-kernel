# Unraid 内核自动构建

本仓库以官方 Unraid 包为基础、只替换内核版本：每日检测官方 Unraid 与
[ich777/unraid_kernel](https://github.com/ich777/unraid_kernel) 上游更新，
有更新即用 ich777 的最新内核重新打包官方镜像，自动触发 GitHub 云编译并
发布 Release，全程无需本地编译。

> i915 SR-IOV 驱动由独立仓库
> [hellomrli/my-i915-sriov-driver](https://github.com/hellomrli/my-i915-sriov-driver)
> 以插件包形式构建与发布，本仓库不再构建或追踪它。

## 最新发布

当前组合：**Unraid 7.4.0-beta.1 / Linux 6.18.44-Unraid**

→ [GitHub Releases](https://github.com/hellomrli/my-unraid-kernel/releases)

| 产物 | 用途 |
| --- | --- |
| `unRAIDServer-...-x86_64.zip` | 完整 USB 安装包，替换官方包中的 `bzimage` 与 `bzroot`，其余文件原样保留 |
| `bzimage-<KERNEL>` / `bzroot-<KERNEL>` | ich777 内核源码用官方 GCC 工具链编译出的内核与模块树 |
| `sha256sums-<KERNEL>.txt` | 上述产物的 SHA-256 校验和 |
| `verification-<KERNEL>.txt` | 静态验证报告（vermagic、编译器、ZFS 版本、模块数等） |

## 快速使用

替换 USB 中的 `bzimage` 与 `bzroot`，**并同步更新配套的
`bzimage.sha256` / `bzroot.sha256`**（`bzmodules`、`bzfirmware`、
`bzroot-gui` 等保持官方原样）。Unraid 启动时用 `.sha256` 旁路文件逐一
校验引导文件（`rc.S` 的 `bzcheck`），缺失或不匹配会直接 `abort`：

```sh
cd /boot
# 备份：回滚启动项指向的备份文件也需要各自的 .sha256
cp -a bzimage bzimage-<旧版本>-stock && cp -a bzimage.sha256 bzimage-<旧版本>-stock.sha256
cp -a bzroot  bzroot-<旧版本>-stock  && cp -a bzroot.sha256  bzroot-<旧版本>-stock.sha256
# 替换；bzimage.sha256 / bzroot.sha256 从 Release 直接下载，
# 文件名与 U 盘布局一致，原样放入即可
cp /path/to/bzimage-<KERNEL> bzimage
cp /path/to/bzroot-<KERNEL>  bzroot
cp /path/to/bzimage.sha256 bzimage.sha256
cp /path/to/bzroot.sha256  bzroot.sha256
# 核对下载文件本身
sha256sum -c sha256sums-<KERNEL>.txt
# 若 Release 未提供侧车文件，可手工生成（bzcheck 只比对前 64 位裸哈希）：
# sha256sum bzimage | cut -c1-64 > bzimage.sha256
# sha256sum bzroot  | cut -c1-64 > bzroot.sha256
```

改用完整 USB zip 的话无需手工操作：包内已带重新生成好的 `.sha256`
文件。救急开关：`touch /boot/config/skipbzcheck` 可跳过启动校验。

**验证**：

```sh
uname -r
modinfo zfs | egrep '^(version|vermagic):'
```

## 自动构建机制

每日 02:30 UTC，`Watch upstream releases` 工作流检测两个上游源：

1. **Unraid 官方**：`releases.unraid.net/json`（最新公开版本，含 beta/rc），
   作为**包的底子**——用户空间、固件、`bzmodules` 等保持官方原样；同时从
   官方 `bzimage` 提取 GCC 版本作为编译工具链（`extract-official-gcc.py`）
2. **ich777/unraid_kernel**：最新 GitHub Release，作为**要替换进去的内核
   版本**（可能比官方自带内核更新）

任一源有更新且原料齐备（官方 zip 可下载、官方 GCC 可提取、ich777 已发布
最新内核源码包）时，自动以 `auto-latest` 目标触发云编译。构建成功即发布
Release 并回写状态文件（`config/upstream-state.env`）；失败则状态不变，
次日重试。已运行/排队中的构建不会重复触发。

**设计原则**：

- **官方为底、只换内核**：保留官方 `bzmodules`/用户空间/固件字节级一致，
  仅把 `bzimage` 与内核模块树替换为 ich777 的内核版本
- **GCC 以官方为准**：容器镜像版本取 `max(15.3.0, 官方内核 GCC)`，官方升级即自动跟随
- **OpenZFS 随内核重建**：新内核版本的 ZFS 模块重新编译，与替换后的内核匹配
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

已知限制：`bzmodules`（挂载在 `/usr` 的 squashfs）保持官方包原样，其中
`/usr/src/linux-<官方内核版本>` 与替换后的内核版本不一致，因此新内核的
`/lib/modules/<版本>/{build,source}` 链接在 NAS 上是悬空的——在机器上
直接编译树外模块（如 NVIDIA、r8125 等源码构建型插件）会缺少匹配的内核
头文件。需要时把 ich777 Release 里对应的 `linux-<版本>.tar.xz` 解压到
可写目录（如 `/opt/src/linux-<版本>-Unraid`）并重定向这两个链接：

```sh
ln -sfn /opt/src/linux-<版本>-Unraid "/lib/modules/<版本>-Unraid/build"
ln -sfn /opt/src/linux-<版本>-Unraid "/lib/modules/<版本>-Unraid/source"
```

`bzmodules` 本身不随 Release 分发：它与官方包逐字节相同（50-verify 会
校验），直接沿用官方文件即可，其校验和包含在 `sha256sums-<KERNEL>.txt` 中。

以上为编译期与静态 ABI 检查，**不保证**运行时稳定性。测试前请备份原 USB
文件并保留恢复启动项。
