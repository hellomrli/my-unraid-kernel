# Unraid i915 SR-IOV kernel builds

This repository publishes experimental Unraid kernels and i915 SR-IOV
packages. The default `main` branch contains the current 6.18 build. Build
inputs and verification notes are kept alongside the scripts and release
documents.

## Branches

| Branch | Contents |
| --- | --- |
| `main` | Unraid 7.4.0-beta.1 with Linux `6.18.44-Unraid`, i915 SR-IOV `2026.08.12.1`, and the beta package's OpenZFS 2.4.3. |
| `7.0` | The previous history: the Unraid 7.3.1 / Linux 7.1.1 build. |

The `main` build is available from the GitHub Releases page. The release
assets include:

- `unRAIDServer-7.4.0-beta.1-Linux-6.18.44-i915-sriov-2026.08.12.1-x86_64.zip`:
  the beta1 USB package with SR-IOV modules merged into its `bzroot`.
- `i915-sriov-202608121-6.18.44-Unraid-2.txz`: the GCC 16.2.0 plugin-compatible driver
  package for an existing 6.18.44-Unraid installation.
- SHA-256 and MD5 checksum files, plus the static verification report.

Use the complete ZIP when replacing the Unraid beta USB contents. It keeps
the official beta `bzimage`, `bzmodules`, `bzfirmware`, bootloader files,
userspace and OpenZFS modules, and replaces only `bzroot` with the SR-IOV
modules merged in. Back up the original USB files and keep a recovery boot
entry before testing.

## Build

The tracked `config/build.env` pins GCC 16.2.0 for the injected SR-IOV
modules. Run the complete build from this directory:

```bash
scripts/all.sh
```

The principal outputs are written to `out/`:

```text
out/unRAIDServer-7.4.0-beta.1-Linux-6.18.44-i915-sriov-2026.08.12.1-x86_64.zip
out/i915-sriov-202608121-6.18.44-Unraid-2.txz
```

The default beta configuration uses the official kernel image and merges the
four SR-IOV modules into the official module tree. It does not rebuild or
replace the OpenZFS modules already present in beta1.

To build only the driver package for stock Unraid 7.3.2 / 6.18.38-Unraid:

```bash
BUILD_ENV_FILE=config/build-6.18.38-plugin.env scripts/all.sh
```

That mode uses the matching prebuilt kernel ABI and produces
`out/i915-sriov-20260808-6.18.38-Unraid-1.txz`.

For the GCC 16.2.0 compatibility build used by the 2026-08-12 test release:

```bash
tool_root=/home/lain/codex/i915/.toolchains/host-tools
PATH="$tool_root/usr/bin:$PATH" \
BISON_PKGDATADIR="$tool_root/usr/share/bison" \
HOSTCFLAGS="-I$tool_root/usr/include" \
HOSTLDFLAGS="-L/usr/lib/x86_64-linux-gnu -L$tool_root/usr/lib/x86_64-linux-gnu" \
BUILD_ENV_FILE=config/build-gcc-16.2.0.env scripts/all.sh
```

This produces the full 6.18.43 package and the revision-2 driver package
`out/i915-sriov-20260808-6.18.43-Unraid-2.txz`.

## GitHub Actions

### Cloud builds (no local compilation)

All compilation happens on GitHub-hosted runners inside the official GCC
container image. The compiler follows the **official Unraid kernel package**:
the build resolves the GCC version embedded in the official `bzimage` (via
`scripts/extract-official-gcc.py`) and uses `max(15.3.0, official GCC)` as the
container image tag. Manual targets are resolved the same way; an explicit
`gcc_version` input always wins.

Two workflows are provided:

- **Build Unraid packages** (`build.yml`) — build one of the manual targets
  (`full-7.4.0-beta.1`, `full-6.18.44`, `full-6.18.43`, `plugin-6.18.38`) or
  `auto-latest` for a fully parameterized build. Enable `publish_release` and
  provide a `release_tag` to attach the outputs to a Release; the Release is
  created automatically when the tag does not exist yet. Outputs are also kept
  as a 14-day Actions artifact. A full build is CPU-, disk-, and
  network-intensive and can take several hours.
- **Watch upstream releases** (`watch-upstream.yml`) — runs daily (02:30 UTC,
  also manually or via `repository_dispatch` with type `check-upstream`) and
  checks the three upstream sources:
  1. the official Unraid releases JSON (`releases.unraid.net/json`, latest
     public version including beta/rc),
  2. the official kernel version + GCC from the official `bzimage`,
  3. the latest `strongtz/i915-sriov-dkms` tag.

  `scripts/detect-upstream.sh` gathers the current state of all three sources;
  `scripts/upstream-compare.py` compares it with
  `config/upstream-state.env` (the last successfully built combination). When
  anything moved and every ingredient is resolvable (ich777 published the
  kernel archive for the official kernel, the i915 commit is pinned), the
  watch workflow dispatches `build.yml` with `target=auto-latest`, a computed
  release tag `v<UNRAID>-<KERNEL>-i915-<REF>`, and the resolved GCC version.

The auto build uses the **stock-integration mode**: it consumes the official
`bzimage`, `bzmodules`, userspace and OpenZFS modules as-is
(`USE_STOCK_BZIMAGE=true`, `MERGE_STOCK_MODULES=true`, `USE_STOCK_ZFS=true`,
`REBUILD_KERNEL=false`) and only replaces `bzroot` with the four SR-IOV
modules merged in. After a successful auto build the workflow advances
`config/upstream-state.env` and pushes it, so the next run is a no-op until an
upstream source moves again. A failed build leaves the state untouched and the
next daily run retries it.

To run a check manually, trigger `Watch upstream releases` from the Actions
tab; the log shows the detected versions, the last built state, and whether a
cloud build was dispatched.

## Boot and install

Use the i915 path and keep `xe` blacklisted:

```text
intel_iommu=on i915.enable_guc=3 i915.max_vfs=7 module_blacklist=xe
```

For the plugin package, verify the checksum and install it while i915 is not
loaded:

```sh
sha256sum -c i915-sriov-202608121-6.18.44-Unraid-2.txz.sha256
upgradepkg --install-new i915-sriov-202608121-6.18.44-Unraid-2.txz
depmod -a 6.18.44-Unraid
```

Reboot into the matching kernel, then check:

```sh
uname -r
modinfo i915 | egrep '^(version|vermagic|origin_kernel):'
```

Do not unload i915 from an active console or pass the physical-function GPU
through to a VM. If initialization fails, boot the recovery entry with
`module_blacklist=i915,xe`.

## Validation

The published 6.18.44 release passed module vermagic, compiler-marker, and
`depmod -e` checks. These are compile-time and static checks only, not a
guarantee of SR-IOV stability on every Intel GPU.
