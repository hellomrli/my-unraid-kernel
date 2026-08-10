# Stock 6.18.38-Unraid i915 SR-IOV 2026.08.08 Plugin

This plugin-only package targets the stock Unraid 7.3.2 kernel. It uses the
matching `6.18.38-Unraid` source tree, configuration, `Module.symvers`, and
`System.map` from `ich777/unraid_kernel`.

Build inputs:

- kernel release: `6.18.38-Unraid`
- strongtz source: tag `2026.08.08`, commit `1a2f7cfe0ceadea9a9f8b2485ed3d0bff0cf1b24`
- external-module compiler: GCC 15.3.0
- stock-kernel compiler: GCC 14.2.0
- archive SHA-256: `b336c66bf1d7ee2cedba88e8be2124b2256c94476b1d1c944518ce8d6bcf37da`

Build with:

```bash
BUILD_ENV_FILE=config/build-6.18.38-plugin.env scripts/all.sh
```

Output:

```text
out/i915-sriov-20260808-6.18.38-Unraid-1.txz
SHA-256 9a8450569c928331bdbf0ce78710fc98fab131f82d08cc388d04f8e822b76559
MD5    436005dea213f3d0012eead9cde95986
```

Both packaged modules report version `2026.08.08-sriov` and vermagic
`6.18.38-Unraid SMP preempt mod_unload`. `depmod -e` against all 1,188 stock
modules reported no unresolved symbols and resolved `i915` to the replacement
module path.

The package was staged on the target Unraid boot device under
`/boot/config/plugins/i915-sriov/packages/6.18.38/`. The previous 2026.05.06
package was retained under `/boot/config/plugins/i915-sriov-backup/`. No
running module was unloaded or replaced; the new package takes effect on the
next normal boot.
