# Unraid 7.4.0-beta.1 i915 SR-IOV 集成

本构建以官方 Unraid 7.4.0-beta.1 USB 镜像为基础，其 Linux
`6.18.44-Unraid` 的 `bzimage`、用户空间、固件和 OpenZFS 2.4.3 模块保持
不变。

固定的 `strongtz/i915-sriov-dkms` `2026.08.12.1` 模块使用 GCC 16.2.0 编译，
替换 `bzroot` 中官方的 i915、kvmgt 和 xe 模块，`intel_sriov_compat` 放在
插件兼容的 `updates/compat` 路径下。合并后重新生成模块元数据，使 SR-IOV
版 i915 模块在模块解析时优先被选中，同时不丢弃测试版的其他内核模块。
独立驱动包使用修订号 `i915-sriov-202608121-6.18.44-Unraid-2.txz`，以区别于
更早的 GCC 15.3.0 构建。

测试版 USB 源在 `config/build.env` 和 `config/build-7.4.0-beta.1.env` 中以
SHA-256 固定。以上只是静态打包检查；GPU 稳定性仍取决于主机硬件和固件。
