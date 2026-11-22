# Incremental independent review: 0008 PPN diagnostic fixes

**Date:** 2026-11-22  
**Status:** **Host-only improvements accepted; physical deployment still blocked pending image provenance.**

## Verified fixes

Applied the incremental patch to the corresponding `0007` source files in an isolated environment. `python3 -m py_compile` and `bash -n` passed.

Executed the **actual** `audit_hardware_compatibility()` function with synthetic but structurally valid inputs:

| Case | Expected readiness | Observed |
| --- | --- | --- |
| Complete verified 16 GB profile | true | true |
| Known firmware / wrong block count | false | false |
| Missing MLC/SLC page counts and row bits | false | false |
| Substring-impersonated firmware | false | false |
| 32 GB logical header with known 16 GB profile | false | false |
| Invalid CE bitmap | false | false |

These **six isolated cases passed**. The developer reports 24/24 wider regression tests, which were not independently executed here because the full native build tree and prior downstream base are not available.

## Remaining high-severity blocker A: build identity is not cryptographically verified

The updated `make-diag-kernelcache.sh` no longer falls back to a candidate zImage: good.

However, it infers that `zImage`, `vmlinux`, and `kernel-config` belong to the **same** build merely because their file modification times differ by at most 300 seconds. This does not prove identity. Two different kernels can be generated or copied within that interval, or timestamps can be restored.

String search for `apple_ppn_probe`, `apple_ppn_geometry`, `apple_ftl`, and `tx_page` in the raw `vmlinux` file is not a substitute for structured symbol-table inspection and verification of the actual disassembled program/erase entry points.

**Required:** A clean, isolated diagnostic kernel rebuild with an immutable manifest of actual `sha256sum` values for `.config`, `vmlinux`, `zImage`, the appended DTB and the final wrapped `kernelcache`. Verify the exact no-write configuration (not substring matches), actual ELF symbols and `-EPERM` stubs from that `vmlinux`. The packaging stage must consume the explicitly identified output of that build and fail if anything differs; timestamp proximity is not enough.

## Remaining high-severity blocker B: reported artifact hashes contradict each other

The earlier report gave the diagnostic kernelcache SHA-256 as `aca998f2...`, with an assembled staging bundle SHA-256 `6ba19f4a...`.

The new `0008` report **keeps that same kernelcache hash and size** but changes the staging bundle SHA-256 to `41debdea...`, zImage-DTB hash from `58bb9bb0...` to `e1b61d89...`, and DTB hash from `e439d528...` to `3cd90ade...`.

This cannot describe a single deterministic round-trip verified kernelcache assembled from the newly reported bundle: the container's unpacked bundle would have to match the bundle actually used.

**Required:** Run the unpack tool against the **final** diagnostic `kernelcache`, hash the extracted bundle, and compare it bit-for-bit with the reported staging bundle. Record all artifact hashes in a single timestamped manifest. If hashes changed, rebuild the kernelcache and publish its **new** correct hash rather than reusing the old value.

## Read-only hardware boundary

Upstream [Project Cascadia PR #52](https://github.com/rzxvx/Project-Cascadia/pull/52) remains open and proves a second **16 GB** package only, not our physical 32 GB package.

**No diagnostic deployment, PPN binding or raw NAND writes are authorized.** Preserve the working RAM/Linux, PMU charging implementation, and baseline boot files.

## Sources

- [Linux kernel ARM zImage documentation](https://docs.kernel.org/5.18/arm/arm.html)
- [Linux Kbuild Makefiles](https://docs.kernel.org/kbuild/makefiles.html)
- [Project Cascadia PR #52](https://github.com/rzxvx/Project-Cascadia/pull/52)
