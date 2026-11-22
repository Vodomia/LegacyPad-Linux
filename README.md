# LegacyPad Linux

Experimental native Linux research for legacy Apple iPad hardware, beginning with **iPad mini 1 (P105AP / iPad2,5)**. This repository tracks reproducible research, engineering audits, review evidence, and patches built on [Project Cascadia](https://github.com/rzxvx/Project-Cascadia).

## Current status (2026-11-22)

- **Working on hardware:** PC-less Linux 6.12 / Alpine 3.24.1 RAM-root boot, touchscreen, Wi-Fi, and PMU charging recovery. Observed positive battery charging current in the candidate image.
- **Not proven:** persistent Linux root on the physical **32 GB** iPad mini 1 NAND package.
- **Safety:** no NAND repartition, raw program/erase, 32 GB flashing, or filesystem shrinking is approved. Known-good RAM images must remain intact.
- **Read-only NAND diagnostics:** host-built candidate under independent review. **Do not deploy.**

## Research and review

- [32 GB NAND readiness research](docs/research/2026-11-22-32gb-nand-readiness.md)
- [Initial independent safety review](docs/reviews/2026-11-22-ppn-diagnostic-independent-review.md)
- [Updated review of incremental 0008 — build provenance still blocked](docs/reviews/2026-11-22-ppn-incremental-0008.md)
- [Cumulative engineering patch 0007 (WIP)](patches/0007-cumulative-32gb-nand-and-hardened-ppn-diag.patch)
- [Incremental correction patch 0008 (WIP)](patches/0008-fix-exact-firmware-full-geometry-and-no-fallback.patch)

The patch is a **downstream diff**, not a self-contained build tree. Its application depends on the upstream Project Cascadia baseline and earlier downstream work. The documented physical 32 GB profile is **unknown**; synthetic tests cannot substitute for on-device read-only identification and offline media verification.

## Upstream credit and licensing

Based on [Project Cascadia](https://github.com/rzxvx/Project-Cascadia) by its contributors, including the PPN geometry work proposed in [PR #52](https://github.com/rzxvx/Project-Cascadia/pull/52). Retain attribution and source notices. Included code patches are governed by their respective SPDX notices (primarily GPL-2.0-only). Apple proprietary firmware and device-specific dumps are intentionally excluded.

This is research-stage software. There is **no public installation release** for 32 GB NAND.
