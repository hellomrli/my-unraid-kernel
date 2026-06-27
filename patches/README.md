# Optional patches

`i915-sriov-dkms-linux-7.1.1-forward-port.patch` is applied automatically by
`scripts/30-build-i915-sriov.sh`. It forward-ports `strongtz/i915-sriov-dkms`
`kernel-v7.0` to the Linux `7.1.1-Unraid` build used by this workspace.

Put kernel patches here and apply them after `scripts/10-prepare-kernel.sh`
and before `scripts/20-build-kernel.sh`.

Examples from `thor2002ro/unraid_kernel` that may be relevant for some Unraid
systems are NVMe quirks, UAS quirks, RMRR relax patches, and EDID fixes. They
are not applied by default because they change behavior outside the i915 SR-IOV
driver request.
