# thor2002ro 额外 8 项改动与 Linux 7.2.3 对照

核对日期：2026-09-05。参考分支为
[`7.1.3-20260705`](https://github.com/thor2002ro/unraid_kernel/tree/57e62eed5dcceec94f1d46e7783d38f33619cddd)，
固定提交 `57e62eed5dcceec94f1d46e7783d38f33619cddd`。对照本项目
`linux-7.2.3` 的补丁序列、准备后的源码及生成配置。

此前核对的官方 beta.2 种子有 10 个补丁，覆盖情况见
[构建测试记录](test-linux-7.2.3-unraid-7.4.0-beta.2.md)。下面这组参考项目改动
需要另外评估；其中 6 项扩展尚未移植，蓝牙固件声明和 BFQ 支持已在当前内核中。

| 参考改动与提交 | 参考项目的处理 | 当前 7.2.3 状态与建议 |
| --- | --- | --- |
| [Intel RMRR 放宽](https://github.com/thor2002ro/unraid_kernel/commit/fdcf0aad6977dd5baedd4bee4249b8b834ae39d6) | 新增 `intel_iommu=relax_rmrr`，将 PCI 设备的 RMRR 视为可放宽 | 未移植；当前只保留主线对 USB/显卡的特定例外。适用于部分旧 HP ProLiant 等设备直通受 RMRR 限制的机器，若移植应保持默认关闭。 |
| [it87 扩展驱动](https://github.com/thor2002ro/unraid_kernel/commit/6cb3078707f78f08673e836f7bd9d8cb35e02f88) | 使用社区扩展版，增加 ITE Super I/O 芯片与传感器支持 | 扩展版未移植；已有主线 `CONFIG_SENSORS_IT87=m`，但没有参考版的 IT8686/IT8688 等支持。按主板芯片需求采用适配 7.2 的维护版本。 |
| [SATA PMP 延时](https://github.com/thor2002ro/unraid_kernel/commit/84799e3ea0397132cd380e24f6f9b9c678c494f8) | 给特定 JMicron PMP 链路设置延时标记，读 SCR 前等待 50 ms | 未移植；7.2.3 已有相关 PMP quirks，但没有这项延时。仅在对应端口倍增器存在识别或复位异常时评估，并保留 7.2.3 新增的设备规则。 |
| [OpenRGB SMBus 支持](https://github.com/thor2002ro/unraid_kernel/commit/3ec0d899428878b5be24a697d70c9823d0e6b857) | 增加 `i2c-nct6775`，将 PIIX4 轮询等待从 250–500 µs 缩短到 25–50 µs | 未移植；当前有常规 PIIX4 驱动，没有该 NCT6775 SMBus 驱动。按 RGB 控制需求选配，缩短共享总线等待时间需验证其他 SMBus 设备。 |
| [BFQ 配置默认值](https://github.com/thor2002ro/unraid_kernel/commit/166ec8c64fb99b9d92a90034c62d3d6fb0b6a980) | 这版提交只删除 deadline/Kyber 的 `default y`，给 BFQ 增加 `default y` | 没有套用该补丁，但当前三个调度器均为 `y`，包括 `CONFIG_IOSCHED_BFQ=y`。无需为获得 BFQ 重复移植；编译默认值不代表设备运行时已选择 BFQ。 |
| [Realtek 蓝牙固件声明](https://github.com/thor2002ro/unraid_kernel/commit/9c83284d28d54473698e95f6558e25419cb1a2a8) | 保留补充 `MODULE_FIRMWARE` 的补丁文件；该提交没有修改 `btrtl.c` | 补丁新增的 12 条声明在 7.2.3 的 `btrtl.c` 中全部存在，无需重复移植。这只证明声明已覆盖，固件文件与设备运行仍需各自验证。 |
| [Crucial SATA SSD LPM 兼容](https://github.com/thor2002ro/unraid_kernel/commit/dcd2170938beed91a111665cdb80989193e1a688) | 对 `CT*BX500*` 和 `CT*MX500*` 添加 `ATA_QUIRK_NOLPM`，禁用链路省电 | 未移植这两条扩大匹配范围的规则；当前已有 `CT*0BX*00SSD1` 等主线规则。对有掉盘/唤醒异常的型号和固件评估，可先按 SATA 链路关闭 LPM 验证，避免将整系列都判为有缺陷。 |
| [Killer/alx WOL](https://github.com/thor2002ro/unraid_kernel/commit/2a90b9eaa5d028e0f34ac88fb743489e17e01022) | 给 Atheros `alx` 添加 WOL 的 ethtool 接口和挂起/关机处理，默认打开 magic packet 与链路唤醒 | 未移植；当前 `CONFIG_ALX=m`，但没有该补丁的 `get_wol`/`set_wol` 实现。适用于使用 alx 的相关网卡，不涵盖所有 Killer 产品；移植时应单独验证关机、挂起和恢复。 |

与 ACS 关系最直接的是 RMRR：ACS override 改变 IOMMU 分组判断，
`relax_rmrr` 放宽固件保留 DMA 内存所带来的设备分配限制。即使分组已拆开，
RMRR 仍可能阻止直通。参考补丁将所有 PCI 设备的 RMRR 都视为可放宽，
若固件仍使用这些区域，可能导致不稳定或数据损坏，因此不能凭分组结果决定启用。

参考分支还包含 CachyOS、Manjaro 整组修改及其他提交；本项目没有导入这两个
发行版补丁集，上表也不宣称列出了参考分支的全部差异。

本次补充审阅只修改文档，没有将上述 6 项扩展加入构建，也没有改变现有产物。
结论来自源码与配置检查；未进行对应硬件的运行时测试。
