# Gemini handoff — evidence-first persistence and 32 GB audit

**Audience:** engineering agent operating in the owner's **local Linux Mint Project-Cascadia checkout**.  
**Language:** all repository contributions, issue/PR titles and research notes in **English**. Turkish summaries to the owner are fine.  
**Authority:** **READ-ONLY investigation + host-only tests only.** No physical iPad writes, destructive commands, flashing, repartitioning, image activation, or PR merge without a later explicit approval.

## Mission

Help make the 32 GB iPad mini 1's Linux system **reproducible after cold boots** while researching, but **not assuming**, safe persistent offline user storage.

Start with:
- [Field bring-up report](../bringup/2026-11-21-32gb-pcless-ram-linux.md)
- [Persistence options](../research/2026-11-21-persistence.md)
- [32 GB geometry and failures](../research/2026-11-21-p105-32gb-nand.md)
- [Safety ADR](../decisions/ADR-0001-ram-first.md)
- [Upstream source](https://github.com/rzxvx/Project-Cascadia) (record exact checked-out SHA)

## Workstream A — inventory and preserve the known-good image

1. In the local Cascadia tree, report `git status --short`, upstream remote and current commit, and a **path-only inventory** of locally modified tracked/untracked files, including `devices/a5/tools/p105-pcless.sh`, `p105` helpers, `sftl*`, `lwvm*`, `nand-volume*`, tests and `.bak` files.
2. Determine how the existing `staging-bundle.bin` embeds the initramfs and how `make-pcless.py` wraps it. Trace the actual `/init`, Alpine root generation and `verify` entrypoints.
3. Identify unmodified known-good host artifacts by sizes and SHA-256; **do not overwrite or clean them**. Do not print or commit actual private keys, firmware bytes, secrets or IPs.
4. Record iBEC image-size limits, peak RAM assumptions, and how to maintain **separate known-good and candidate bundles**. Report if any rollback procedure is not truly power-fail-safe.
5. Produce a concise source-map and a **host-only** test plan to integrate **one small non-secret utility or setting** into the RAM image. No iPad transfer/activation until separately approved.

## Workstream B — independent 32 GB storage research

1. Read upstream `lwvm.py`, `lwvmw.c`, `sftl_lwvm.c`, `sftl_mount.c`, `sftl.h`, `nand-volume.sh`, HFS shrink helpers, PPN/FTL driver and tests. Compare every relevant constant/translation with local diffs.
2. Compare [openiBoot's capacity-dependent chunk shift](https://github.com/iDroid-Project/openiBoot/blob/master/bdev.c): `32 - __builtin_clz((mediaSize-1) >> 10)`. Check the consequences of **32,000,000,000-byte media** and a 1024-entry LwVM map. An unrelated iOS 8.4.1 ARMv7 [32 GB IOMedia registry dump](https://github.com/arx8x/iOS-IOMedia-IOKit-dumps/blob/master/IOMedia_iOS_8.4.1_HFS_armv7_home_depot.ioreg) is context, not device-specific proof.
3. Trace the two divergent LwVM header copies previously reported. A 4 KiB file with no LwVM magic or a plausible media size is **not** a valid recovery image. Use local existing snapshots **read-only**, never “repair” a header.
4. Trace physical NAND PPN firmware and geometry assumptions (block size/count, bus, die, CAU, boot blocks, FTL context), and mark each *observed*, *derived*, *unknown*.
5. Produce unit tests that generate/check **synthetic** 16 GB and 32 GB headers and reject invalid maps/bounds. Never use a real disk device as a test destination.
6. Explicitly state that passing host simulators does **not** authorize flash/partition writes or prove iOS boot recovery.

## Workstream C — media and state design

1. Explain how immutable app provisioning can survive cold boots **without** an on-device writable Linux filesystem; do not claim media/bookmark persistence.
2. Identify the minimum user-state file format (e.g., versioned JSON or SQLite if measured feasible), export method and future backend interface. Avoid secrets in image/repository.
3. Estimate bundle-size/RAM costs for a very small launch/player stack, using Alpine 3.24 **armhf** packages; do not equate GPU rendering with H.264 hardware decoding.
4. Define offline cold-boot acceptance tests separately for **system image**, **media player**, and **persistent user state**.

## Deliverables

- A short English research report with file/line references, tested claims, open risks, primary-source links and a **GO/NO-GO** matrix.
- A source-only, reviewable proposed patch for a **host-only custom RAM image experiment**, with tests and rollback plan; leave physical deployment gated.
- A separate 32 GB NAND compatibility audit and test-only patch if useful. No writer enabling by default and no device experiment.
- A sanitized import plan for local `p105-pcless.sh` and related original changes into `Vodomia/LegacyPad-Linux`; keep Cascadia attribution and GPL-related notices. Do not copy proprietary firmware or passwords.
- Final summary to owner: what is **measured** on hardware, what is **tested only on host**, what still blocks offline data persistence, and the **single next owner decision**.

**Stop and ask** before any write to the device, git history rewriting, deletion/cleanup of backups, remote push/merge, physical NAND/FTL mutation, iOS partition update, or experiment capable of losing the known-good boot path. Do not call this “100% safe”: uncertainty must remain explicit.
