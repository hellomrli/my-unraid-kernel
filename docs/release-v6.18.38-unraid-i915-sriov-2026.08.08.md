# 官方 6.18.38-Unraid i915 SR-IOV 2026.08.08 插件

本纯插件包面向官方 Unraid 7.3.2 内核。它使用来自 `ich777/unraid_kernel`
的配套 `6.18.38-Unraid` 源码树、配置、`Module.symvers` 和 `System.map`。

构建输入：

- 内核版本：`6.18.38-Unraid`
- strongtz 源码：标签 `2026.08.08`，提交 `1a2f7cfe0ceadea9a9f8b2485ed3d0bff0cf1b24`
- 外部模块编译器：GCC 15.3.0
- 官方内核编译器：GCC 14.2.0
- 源码包 SHA-256：`b336c66bf1d7ee2cedba88e8be2124b2256c94476b1d1c944518ce8d6bcf37da`

构建命令：

```bash
BUILD_ENV_FILE=config/build-6.18.38-plugin.env scripts/all.sh
```

产物：

```text
out/i915-sriov-20260808-6.18.38-Unraid-1.txz
SHA-256 9a8450569c928331bdbf0ce78710fc98fab131f82d08cc388d04f8e822b76559
MD5    436005dea213f3d0012eead9cde95986
```

打包的两个模块都报告版本 `2026.08.08-sriov`、vermagic
`6.18.38-Unraid SMP preempt mod_unload`。对全部 1,188 个官方模块执行
`depmod -e` 无未解析符号，`i915` 解析到替换后的模块路径。

该包已部署到目标 Unraid 启动设备的
`/boot/config/plugins/i915-sriov/packages/6.18.38/`。之前的 2026.05.06 包
保留在 `/boot/config/plugins/i915-sriov-backup/`。没有卸载或替换正在运行
的模块；新包在下次正常启动时生效。
