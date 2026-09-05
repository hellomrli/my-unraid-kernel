# Unraid 内核自动构建

本仓库以官方 Unraid 包为基础、只替换内核版本：每日检测官方 Unraid 与
[ich777/unraid_kernel](https://github.com/ich777/unraid_kernel) 上游更新，
有更新即用 ich777 的最新内核重新打包官方镜像，自动触发 GitHub 云编译并
发布 Release，全程无需本地编译。

> i915 SR-IOV 驱动由独立仓库
> [hellomrli/my-i915-sriov-driver](https://github.com/hellomrli/my-i915-sriov-driver)
> 以插件包形式构建与发布，本仓库不再构建或追踪它。

本实验分支的测试组合为 **Unraid 7.4.0-beta.2 / Linux 7.2.3-Unraid /
OpenZFS 2.4.4 / GCC 15.3.0**。内核来自 kernel.org，配置和阵列驱动以
`6.18.47-Unraid` 为种子；构建方法、验证结果及移植范围见
[beta.2 测试记录](docs/test-linux-7.2.3-unraid-7.4.0-beta.2.md)。

该组合已通过 [GitHub Actions 云编译](https://github.com/hellomrli/my-unraid-kernel/actions/runs/33977957223)，
可[下载预发行版 v7.4.0-beta.2-7.2.3-Unraid](https://github.com/hellomrli/my-unraid-kernel/releases/tag/v7.4.0-beta.2-7.2.3-Unraid)。
Release 附带完整 USB ZIP、引导文件、校验清单及两份静态验证报告。

## 最新发布

常规分支的已发布组合见 [GitHub Releases](https://github.com/hellomrli/my-unraid-kernel/releases)。

| 产物 | 用途 |
| --- | --- |
| `unRAIDServer-...-x86_64.zip` | 完整 USB 安装包，替换官方包中的 `bzimage` 与 `bzroot`，其余文件原样保留 |
| `bzimage-<KERNEL>` / `bzroot-<KERNEL>` | 所选内核源码用配套 GCC 工具链编译出的内核与模块树 |
| `sha256sums-<KERNEL>.txt` | 上述产物的 SHA-256 校验和 |
| `verification-<KERNEL>.txt` | 静态验证报告（vermagic、编译器、ZFS 版本、模块数等） |
| `verification-extended-<KERNEL>.txt` | 全部模块、官方 ZIP 条目、引导文件及校验清单的验证结果，JSON 格式 |

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
# 核对 U 盘上的引导文件与配套侧车，避免复制时混用不同构建的文件
for name in bzimage bzroot; do
  test "$(head -c64 "$name.sha256")" = "$(sha256sum "$name" | cut -c1-64)" || exit 1
done
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

## ACS override（VFIO）

本实验内核保留官方 beta.2 的 `pcie_acs_override` 支持，默认关闭。它用于
PCIe 设备没有 ACS、导致多个设备落在同一个 IOMMU group 时，让 VFIO 按更细
的拓扑建立分组。它只改变 Linux 的判断，不会改变交换机或根端口的实际
DMA 隔离；因此可能允许虚拟机通过 peer-to-peer DMA 访问同组设备或主机内存。
仅应在可信虚拟机、确认硬件拓扑后使用。

先查看设备和分组：

```sh
lspci -nn
find /sys/kernel/iommu_groups -type l -printf '%p -> %l\n'
```

确认确实需要拆分后，在 `/boot/syslinux/syslinux.cfg` 对应启动项的
`APPEND` 行加入参数并重启。优先使用范围最小的形式：

```text
pcie_acs_override=id:vvvv:dddd
```

其中 `vvvv:dddd` 是 `lspci -nn` 显示的厂商和设备 ID，会匹配所有同 ID
设备，不能限定单个 PCI 地址。也可以按需使用 `downstream`（所有下游/根
端口）或 `multifunction`（多功能端点）：

```text
pcie_acs_override=downstream,multifunction
```

启动日志会打印 ACS override 警告。若设备本身已有 ACS capability，内核不会
覆盖它；若不再需要，删除启动参数即可恢复原始分组。

## beta.2 硬件兼容补丁

7.2.3 实验分支还带入官方 beta.2 的 NVMe quirks、mvsas 2782、Mozart
395S、Thunderbolt host reset 默认值和 DRM EDID 日志补丁。它们按设备 ID 或
驱动默认行为生效，完整清单和适用范围见
[`linux-7.2.3-hardware.series`](patches/linux-7.2.3-hardware.series)及
[测试记录](docs/test-linux-7.2.3-unraid-7.4.0-beta.2.md)。旧版
`raid6_choose_xor` 没有套用，因为 7.2.3 已用 static call 提供等价的 XOR
后端，直接移植会与新接口冲突。

官方 beta.2 的 MD Kconfig/Makefile 改动由
[`10-prepare-kernel.sh`](scripts/10-prepare-kernel.sh) 重建，Seagate UAS 改动
包含在 [`unraid-driver-linux-7.2.3-port.patch`](patches/unraid-driver-linux-7.2.3-port.patch)
中；在这 10 个官方补丁中，只有 `raid6_choose_xor` 没有直接移植。
此范围不包含 thor2002ro 参考项目的额外修改；其 RMRR、it87、SATA/PMP、
OpenRGB、BFQ、蓝牙和 WOL 等 8 项改动的核对结果见
[参考项目补丁审阅](docs/review-thor-extra-patches-linux-7.2.3.md)。

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
# 本分支实验目标（先把 GCC 15.3.0 的 bin 目录加入 PATH）
BUILD_ENV_FILE=config/build-linux-7.2.3.env scripts/all.sh
```

## 验证与限制

每个发布在上传前均通过静态验证（`scripts/50-verify.sh`）：逐一检查全部模块的
ELF、vermagic、配置指定的 GCC 版本及 XZ CRC32，并用 `modules.order` 检查模块
是否遗漏。还会确认 Unraid MD / OpenZFS 模块身份与版本、`depmod -e` 无未解析
符号，以及打包的 bzimage 与构建目录中的镜像一致。

完整 ZIP 的文件清单必须与官方一致，除 `bzimage`、`bzroot` 和对应两个
SHA256 文件外，所有条目内容必须保持官方原样。ZIP 内的引导文件、独立下载
文件、裸哈希侧车和两份 SHA256 清单相互核对；bzroot 的早期归档和模块目录
以外全部 CPIO 记录（含顺序、属主、权限）也须原样保留。每次验证会重新生成
基础与扩展报告，验证失败时清除这两份旧报告。

`Check build scripts` 工作流在脚本或工作流变更的 push / PR 上运行回归测试，
完整云编译也运行同一套测试，并上传扩展报告。实验目标 `full-linux-7.2.3`
发布为预发行版；新 Release 的标签指向实际构建提交，全部附件上传后才公开。
本地可先运行：

```bash
# 依赖 Python 3、GCC、cpio、gzip、zstd
python3 -m unittest discover -s scripts/tests -v
# 已有构建产物时可单独重新验证
BUILD_ENV_FILE=config/build-linux-7.2.3.env scripts/50-verify.sh
```

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
