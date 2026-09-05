# Unraid 7.4.0-beta.2 / Linux 7.2.3 测试记录

测试日期：2026-09-05。此组合在 `linux-7.2.3` 实验分支本地构建。

## 官方基座与来源

[官方发布说明](https://docs.unraid.net/unraid-os/release-notes/7.4.0/)标注
beta.2 发布于 2026-09-03，包含 mover 进度显示、Power Options 修复及基础
软件更新。对构建相关的变化，已直接核对官方 ZIP：

| 项目 | 官方 beta.2 | 本测试组合 |
| --- | --- | --- |
| Unraid 用户空间 | 7.4.0-beta.2 | 保留官方文件 |
| 内核 | 6.18.47-Unraid | kernel.org Linux 7.2.3，加 Unraid MD / Seagate UAS 移植 |
| GCC | 15.3.0 | 15.3.0（本地工具链，宿主 Binutils 2.46） |
| OpenZFS | 2.4.4 | 2.4.4-1 模块，匹配官方用户空间 |

预发布信息须用官方接口
[`json?includePublic=1`](https://releases.unraid.net/json?includePublic=1)查询，
默认 `/json` 列表不包含此次 beta。ZIP 下载地址从返回的 changelog 同目录确定，
完整地址和各源码校验值均锁定在
[`config/build-linux-7.2.3.env`](../config/build-linux-7.2.3.env)。

官方 ZIP 的 SHA256（下载后计算，API 未提供该值）：

```text
b214c9583bff4bdb3847a7ca1cc43fc7b31c8e6a2995a8c2727185ccccb9f9fc
```

ZIP CRC 检查及包内全部 6 个官方 SHA256 侧车检查通过。
`bzmodules` 中 `src/linux-6.18.47-Unraid/config` 与 ich777 种子的 `.config`
仅有 15 个编译工具检测项不同，硬件功能配置一致。三个阵列驱动源文件
`md_unraid.c`、`md_unraid.h`、`unraid.c` 与官方包逐字节相同。

此前使用 6.18.44 种子会遗漏后来增加的 Hyper-V、RTW89 USB、音频、手柄、
传感器等配置。本次已换成 6.18.47 种子。`olddefconfig` 的
`NETFILTER_NETLINK=m` 警告来自 7.2.3 将该选项改为 bool，结果为 `y`；
Docker 所需的 netfilter / bridge 配置仍保留。

[OpenZFS 2.4.4](https://github.com/openzfs/zfs/releases/tag/zfs-2.4.4)正式支持
Linux 4.18–7.2，因此已将原分支的 2.4.99 开发快照换为 2.4.4 正式版。

## 本次修复

官方 beta.2 的 10 个内核补丁已与种子源码逐一核对。MD Kconfig/Makefile
改动由准备脚本重建，Seagate UAS 改动包含在 Unraid 驱动移植补丁中；除
旧版 `raid6_choose_xor`（见下文）外，7.2.3 现已前移以下硬件补丁，
补丁序列见 [`patches/linux-7.2.3-hardware.series`](../patches/linux-7.2.3-hardware.series)：

| 补丁 | 作用 |
| --- | --- |
| ACS override | 保留 `pcie_acs_override=` 的 VFIO 分组覆盖，默认关闭 |
| NVMe quirks | 增加 6 个官方请求的 PCI ID，并给 3 个既有 ID 补齐 quirk flag |
| mvsas 2782 | 让 TTI/HighPoint RocketRAID 2782 使用 `chip_9480` |
| Mozart 395S | 对 Yuan Yuan/Elgato HD60 Pro 禁止会使采集卡失效的 bus reset |
| Thunderbolt host reset | 默认跳过 USB4 host router reset，仍可用模块参数启用 |
| DRM EDID | 将全零或损坏 EDID 的两条常规日志从 `pr_notice` 降为 `pr_debug` |

NVMe quirk 只按厂商/设备 ID 匹配，具体设备仍应以 `lspci -nn` 和实际日志
确认。Mozart 的 `NO_BUS_RESET` 会减少 VFIO 可用的复位方式，属于该采集卡
的必要兼容取舍。Thunderbolt 改变的是默认值，不会禁止
`thunderbolt.host_reset=1`；遇到需要复位才能枚举的设备时可显式恢复。

以上覆盖范围限于官方 beta.2 种子的补丁。thor2002ro 参考项目额外的 RMRR、
it87、SATA/PMP、OpenRGB、BFQ、蓝牙与 WOL 等 8 项改动另见
[对照审阅](review-thor-extra-patches-linux-7.2.3.md)；其中 6 项扩展尚未移植，
蓝牙固件声明与 BFQ 支持已由当前内核提供。

原 `40-package-unraid.sh` 用 `cpio --owner=0:0` 重打包整个根文件系统，
导致 beta.2 的 27 个非 root 属主/组条目丢失原有元数据。例如
`var/lib/nfs/sm` 原为 `32:32 / 0700`，改成 root 后会阻止对应服务访问。

新的 `repack-bzroot.py` 直接保留官方早期归档和模块目录以外的原始 newc
记录，只替换 `lib/modules`。官方属主、权限、内容、符号链接、硬链接及
设备节点均保留；新模块使用独立 inode 编号，避免与官方记录产生硬链接
冲突。此流程无需以 root 身份解包。

`50-verify.sh` 增加上述归档一致性检查。解包和重打包共用 `scripts/bzroot.py`
的 CPIO 解析器，按记录长度定位归档边界；旧解包脚本会把早期文件内容中的
`TRAILER!!!` + zstd magic 误认为边界，此问题已通过命令行回归测试复现并修复。
解析器还校验 CRC newc 的内容校验值，并在解包前验证全部归档成员。

原来只在本地临时脚本里执行的全量模块与 ZIP 检查，现已移入
[`scripts/verify-artifacts.py`](../scripts/verify-artifacts.py)，由 `50-verify.sh`
统一调用：

- 全部模块逐一检查 ELF、vermagic、GCC 版本、XZ CRC32；用 `modules.order`
  核对内核模块清单，并确认 Unraid MD 与 OpenZFS 模块身份、版本。
- ZIP 的条目清单及所有保留文件必须匹配官方；ZIP 内引导文件、独立文件、
  裸哈希侧车和 SHA256 清单必须一致，重复或缺失条目会报错。
- 官方 bzroot 基线直接从通过校验的官方 ZIP 读取，避免误用旧解包目录；
  归档检查同时保留非模块记录的原有顺序。
- 验证前清除基础与扩展旧报告，通过后写入当前产物的检查结果与哈希。
  此前 `out/verification-extended-7.2.3-Unraid.txt` 残留了上一轮构建的哈希，
  已由本次正式验证重新生成并与下表对齐。

25 项回归测试覆盖权限与硬链接保留、伪 magic、损坏归档、错误模块、遗漏模块、
校验文件错配和旧报告失效等情况；独立的 `Check build scripts` 工作流和完整
云编译均运行这套测试。云编译产物清单增加扩展报告，Release 说明也去掉了
将所有内核固定归为 ich777 来源的错误描述。

## 构建与验证

使用全新的独立构建目录，完整运行环境检查、来源校验、准备源码、内核和
模块编译、OpenZFS 编译、打包、静态验证。

```bash
export PATH=/path/to/gcc-15.3.0/bin:$PATH
python3 -m unittest discover -s scripts/tests -v
BUILD_ENV_FILE=config/build-linux-7.2.3.env scripts/all.sh
```

本地还需安装 README / `00-check-env.sh` 所列依赖。若已有
`build/linux-7.2.3` 来自旧种子，应使用新的构建目录，或在本地配置副本中
设置 `FORCE_PREPARE=true`；`CLEAN_KERNEL_BUILD` 只清理对象文件，不会刷新
已准备的配置或补丁。

验证结果：

- Linux 7.2.3 `bzImage`、全部内核模块及 OpenZFS 2.4.4 编译通过；NVMe、
  mvsas、PCI quirks、Thunderbolt 和 DRM EDID 的修改均经过对应对象编译。
- 1293 个模块全部通过 ELF、vermagic、GCC 15.3.0 和 XZ CRC32 检查；
  `md-mod` 描述为 `unRAID array stacking driver`。
- `depmod -e` 报告为空，未发现未解析的内核符号。
- ZIP 完整性、引导文件侧车校验值通过；只替换 `bzimage`、`bzroot` 及
  两个对应 SHA256 文件，其他 45 个 ZIP 条目与官方内容一致。
- 官方早期归档的 18,014,208 字节和主归档的 2692 条非模块 CPIO 记录
  原样保留，包括上述 27 项非 root 属主/组元数据。
- 回归测试 25/25 通过，Shell 语法、工作流 YAML 解析和 `git diff --check`
  通过。内核编译出现少量上游驱动栈帧超过配置阈值的警告，未出现编译错误。

产物位于仓库的 `out/`：

| 文件 | SHA256 |
| --- | --- |
| `unRAIDServer-7.4.0-beta.2-Linux-7.2.3-x86_64.zip` | `d6fcf0a0df83fb784c9fdf423e0dc8e8158d96498e32fa5b478c3d899cc2e92a` |
| `bzimage-7.2.3-Unraid` | `ee0a9e486ef112cced3dd816c6279183d56d66c7e5c777ca089db1d83911a7d9` |
| `bzroot-7.2.3-Unraid` | `ea1a2a28d142754377c62626e674883d2d531547277f725608b5aa0afc6cd75e` |
| 官方 `bzmodules` | `5d7f28bbf9882457abc258ea38c77dddd97f0a193940eb8c5f843e10be9fdf21` |

同时提供 `bzimage.sha256`、`bzroot.sha256`、完整 SHA256 清单、
`verification-7.2.3-Unraid.txt` 和 `verification-extended-7.2.3-Unraid.txt`。
本机的构建日志、源码和模块暂存树保留在 `build/test-beta2/`；扩展验证的正式
入口为 `scripts/50-verify.sh`，后续复验日志为
`logs/verify-beta2-continuation.log`。
公开 Release 使用下节记录的 GitHub Actions 云编译产物。

以上哈希来自包含整组硬件补丁的干净目录全量重建；`bzmodules` 仍为官方文件，
校验值为 `5d7f28bbf9882457abc258ea38c77dddd97f0a193940eb8c5f843e10be9fdf21`。
补齐验证流程后，使用这组既有产物重新运行正式静态验证并通过；重打包解析器
还用官方 bzroot 和已有模块归档做了集成检查，生成的全部 4397 条主归档记录
与当前 bzroot 一致。

测试 USB 应先使用本次完整 beta.2 ZIP 的基座；仅替换引导文件时，需要先
确认 USB 已升级到官方 beta.2，再成对复制 `bzimage`、`bzroot` 和两个
配套 SHA256 文件，避免与 beta.1 用户空间混用。

## 云端构建与发布

北京时间 2026-09-06 01:22，已从 `linux-7.2.3` 分支的提交
[`6cb9449`](https://github.com/hellomrli/my-unraid-kernel/commit/6cb9449574b29804235d6b8d3036a71678e89841)
完成 [GitHub Actions 构建](https://github.com/hellomrli/my-unraid-kernel/actions/runs/33977957223)，
并公开[预发行版 v7.4.0-beta.2-7.2.3-Unraid](https://github.com/hellomrli/my-unraid-kernel/releases/tag/v7.4.0-beta.2-7.2.3-Unraid)。
Release 标签指向该构建提交，全部 11 个附件上传完成后才公开。

云端使用 GCC 15.3.0，25 项回归测试通过；1293 个模块的全量静态验证通过，
45 个官方 ZIP 保留条目、2692 条非模块 CPIO 记录和早期归档一致性检查通过。
发布后另行下载校验清单与报告，确认 GitHub 的附件 SHA256 与云端记录一致。
完整检查结果见 Release 的
[扩展报告](https://github.com/hellomrli/my-unraid-kernel/releases/download/v7.4.0-beta.2-7.2.3-Unraid/verification-extended-7.2.3-Unraid.txt)。

| 云端发布文件 | SHA256 |
| --- | --- |
| `unRAIDServer-7.4.0-beta.2-Linux-7.2.3-x86_64.zip` | `89936d7ed8e4b0482ff5e5436cfc551c1adee7dd0d112c0b298de3eb4810cfcf` |
| `bzimage-7.2.3-Unraid` | `38596254ae1fb43ca8ebccdda5b8c11f87fa59a0607544756772e11902008ea6` |
| `bzroot-7.2.3-Unraid` | `5f9ead7d31d58454549a9d5dd960647d0e2c8bf142dc260573be3d2e03bce8f3` |

## 尚待处理和测试的范围

- 已将官方 beta.2 的 ACS override 前移到 7.2.3。内核保留
  `pcie_acs_override=downstream`、`multifunction` 和 `id:vvvv:dddd` 参数，
  但默认不启用；只有在启动参数中明确指定时才会改变 IOMMU 分组。该功能
  只改变内核的隔离判断，不会给没有 ACS 的 PCIe 交换机增加硬件隔离能力，
  启用后可能允许未受 IOMMU 保护的 peer-to-peer DMA，不适合不可信虚拟机。
- RAID6 的 `raid6_choose_xor.patch` 没有直接套用。7.2.3 的 RAID6 已通过
  `raid6_xor_syndrome()` 和 static call 选择算法；本目标为 x86_64，SSE2、
  AVX2、AVX512 后端均提供 XOR 更新实现。旧补丁针对的是早期函数指针接口，
  强行套用会重复定义符号并破坏新的选择逻辑。
- DRM EDID 补丁只降低日志级别，不修复显示器返回的坏 EDID；需要显示兼容性
  修复时仍应使用显示器/显卡对应的 EDID 固件或驱动 quirk。
- 本次没有实机硬件回归环境；mvsas、NVMe、Mozart、Thunderbolt 和 ACS 的
  运行时行为仍需在对应设备上验证。ACS 还应核对
  `/sys/kernel/iommu_groups` 的实际分组变化。
- `10-prepare-kernel.sh` 现已为 MD Makefile 钩子加入官方对
  `md-autodetect.o` 的 `CONFIG_MD_UNRAID` 排除保护；本次配置
  `BLK_DEV_MD=m`，该分支未实际触发内建 MD 路径。
- 保留的官方 `bzmodules` 内只有 6.18.47 的 `/usr/src` 资料；测试机现场
  编译树外模块需要另行提供本次准备、编译后的 7.2.3 源码及配置。
- 编译和归档验证不能代替实机启动、阵列读写/校验、ZFS 池操作及设备测试；
  i915 SR-IOV 插件由独立项目提供，也未在本次测试中验证。
