# Unraid 7.4.0-beta.1 i915 SR-IOV integration

This build starts from the official Unraid 7.4.0-beta.1 USB image and keeps
its Linux `6.18.44-Unraid` `bzimage`, userspace, firmware and OpenZFS 2.4.3
modules unchanged.

The pinned `strongtz/i915-sriov-dkms` `2026.08.12.1` modules are built with
GCC 16.2.0 and replace the stock
i915, kvmgt and xe modules in `bzroot`, with `intel_sriov_compat` added under
the plugin-compatible `updates/compat` path. The module metadata is regenerated
after the merge so the SR-IOV i915 module wins module resolution without
discarding the beta's other kernel modules. The standalone driver package uses
revision `i915-sriov-202608121-6.18.44-Unraid-2.txz` to distinguish it from the
earlier GCC 15.3.0 build.

The beta USB source is pinned by SHA-256 in `config/build.env` and
`config/build-7.4.0-beta.1.env`. This is a static packaging check; GPU
stability still depends on the host hardware and firmware.
