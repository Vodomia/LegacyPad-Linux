# Independent review — P105AP read-only PPN diagnostic

**Date:** 2026-11-22  
**Decision:** **BLOCKED / DO NOT DEPLOY**  
**Scope:** Host-only inspection of supplied `0007-cumulative-32gb-nand-and-hardened-ppn-diag.patch`; no physical iPad operations.

## Confirmed progress

The downstream patch now includes actual PPN/SFTL driver sources based on upstream Project Cascadia PR #52, a diagnostic kernel config, held-probe DTS bootargs, and more defensive dmesg parsing.

Upstream `Kbuild` has a conditional `-DSFTL_NO_WRITE` path when `CONFIG_APPLE_SFTL_WRITE` is disabled. The supplied config requests `CONFIG_APPLE_PPN=y` and `CONFIG_APPLE_SFTL=n`; the reported ARM disassembly shows program/erase returning `-EPERM`. This disassembly was **reported by Gemini**, not independently reproduced from the user's host-built `vmlinux`.

The upstream `apple_ppn_probe()` returns `-ENXIO` while `hold_probe=1`; later explicit binding can initiate a probe. No raw NAND write is authorized.

## Reproduced fail-open bugs

Independent execution of the supplied `nand_diagnose.py` in an isolated host environment shows that `audit_hardware_compatibility()` still returns `overall_driver_ready=True` in all three cases below. In every case, an otherwise synthetically valid 16 GB LwVM primary/backup header and CE bitmap `0101` were provided:

| Case | Inputs | Observed (incorrect) |
| --- | --- | --- |
| Mismatched known profile | Firmware `030800P` but **1064** blocks/CAU (instead of 2088) | `True` |
| Incomplete physical geometry | Firmware `030800P`, 2088 blocks, but **no** MLC/SLC pages, page/block/CAU row-bit measurements | `True` |
| Forged substring match | Firmware `X030800P_FAKE` with 2088 blocks | `True` |

Root causes: `if prof_key in fw` accepts substrings; mismatched blocks fall through to a broad `elif blocks == 1064 or blocks == 2088` "SUPPORTED" branch; missing geometry fields are never required. Existing 21 passing synthetic tests do not cover these negative cases.

## Image provenance/build issue

`make-diag-kernelcache.sh` selects any existing `devices/a5/build/out/zImage` larger than 10 MB, regardless of whether that image was compiled with the diagnostic config. If absent, it **falls back** to extracting a raw zImage from `candidate-zImage-dtb`. It appends the read-only DTB but does not verify that the selected binary is the reported `vmlinux` with stripped write paths.

Thus the DTB bootargs and IMG3 round-trip test alone cannot prove that the wrapped diagnostic `kernelcache` contains the no-write kernel. The diagnostic assembly must fail closed unless the source `zImage`, `vmlinux`, `System.map`, and `.config` are from the same explicitly validated diagnostic build.

The provided research text also contains an outdated `c9fd3b87...` hash in its executive summary, while its manifest states diagnostic kernelcache `aca998f2...`. Reconcile all records before hardware use.

## Required fixes before any device test

1. Enforce exact normalized firmware identity, exact per-profile **complete** geometry (blocks, MLC/SLC pages, row page/block/CAU bits), CE bitmap, and logical capacity; any missing or mismatched evidence must be `BLOCKED` or `UNVERIFIED`.
2. Add negative regression cases reproducing all three examples above. Run the actual audit function; no hardcoded-string-only tests.
3. Make the build explicitly select a verified diagnostic zImage. Prove and bind the build identity to the final wrapped kernelcache by recorded hashes and disassembly from the **same** `vmlinux`. Forbid fallback to candidate or stale generic zImage.
4. Reconcile diagnostic artifact manifests and remove host-specific paths from documentation/code defaults.
5. Re-run all host-only regression, source, and boot packaging checks. Preserve known-good images unchanged.
6. Only after independent review, request separate explicit permission for any physical diagnostic boot. **No** NAND program/erase/repartition until the physical 32 GB package and FTL profile are independently characterized.

## Sources

- [Project Cascadia upstream PPN driver](https://github.com/rzxvx/Project-Cascadia/blob/main/devices/a5/patches/files/drivers/mtd/nand/apple/apple_ppn.c)
- [Project Cascadia Kbuild](https://github.com/rzxvx/Project-Cascadia/blob/main/devices/a5/patches/files/drivers/mtd/nand/apple/Kbuild)
- [Upstream geometry PR #52](https://github.com/rzxvx/Project-Cascadia/pull/52)
- [Linux driver binding documentation](https://docs.kernel.org/driver-api/driver-model/binding.html)
