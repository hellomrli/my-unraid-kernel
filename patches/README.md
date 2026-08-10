# Patches

`strongtz-2026.08.08-unraid-6x-slab.patch` is applied to the pinned strongtz
2026.08.08 source before compiling it for `6.18.38-Unraid` or
`6.18.43-Unraid`.

The Unraid 6.18 tree backports the two-argument `kmalloc_obj` family from a
newer kernel API. The strongtz source supplies optional-GFP compatibility
forms, but the backported macros remain defined and cause preprocessing
errors. The patch undefines those helpers only on kernels below 7.0 before the
driver compatibility definitions are evaluated. Its 7.0/7.1 path is
unchanged.

The older `i915-sriov-dkms-linux-7.1.1-forward-port.patch` belongs to the main
branch's Linux 7.1.1 experiment and is not used by this branch.
