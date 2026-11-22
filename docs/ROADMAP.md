# Roadmap and acceptance gates

All milestones require physical-device evidence and a reviewable PR before they are marked complete. This document records the owner's **2026-11-22 priority decision**: Linux completion first, YouTube last and optional. Do not start another low-resolution playback proof of concept.

## P0 — Establish project baseline

- [x] First 32 GB iPad mini boots standalone Linux with Wi-Fi and SSH.
- [x] Capture current Alpine/RAM/GPU/audio/package baseline.
- [x] Document architecture, risks, upstream provenance and agent rules.
- [ ] Choose an original-code license compatible with any incorporated GPL-2.0 upstream components.
- [x] Rename the working repository to `LegacyPad-Linux`; it was made public on 2026-11-21 to give the local engineer access. Audit future commits for secrets and sensitive artifacts.

## P1 — Reliable PC-less Linux and charging **(current priority)**

- [ ] Preserve and independently verify the exact known-good image, current iOS boot artifacts, hashes, and recovery path before updating anything.
- [ ] Finish an independently reproducible, full candidate build with the charging patch and read-only `legacypad-charge-gate` included. Host tests and GitHub CI are prerequisites, **not physical acceptance**.
- [ ] Under separate owner authorization, update only the existing PC-less iOS System boot artifacts, keeping the previous image and rollback available. Never alter the 32 GB partition table or FTL in this phase.
- [ ] With suitable wall power and the device charged in iOS, verify actual **positive net battery current**, temperature and input-current behavior under Linux. Run the documented attended six-minute charging gate; then verify sustained charging under an ordinary system workload.
- [ ] Demonstrate two cold boot cycles, including one without Wi-Fi; verify clean return to iOS, charging under iOS and rollback on a failed candidate.

**Gate:** demonstrated, repeatable, recoverable Linux boot and measured stable charging on **this physical iPad**. Do not claim completion from simulations.

## P2 — Durable offline Linux installation and settings

- [ ] Independently characterize the owner's physical 32 GB PPN/FTL and LwVM mapping (32 MiB chunks, header at LBA 0 and proposed backup LBA 8191), including firmware and block/CAU topology, by **read-only** methods.
- [ ] Audit all capacity assumptions, iOS filesystem resize operations, Linux driver mapping, repair paths and restoration requirements before even considering a NAND write.
- [ ] Compare viable persistent root/data strategies against the requirement that the iPad works **without a home computer or network**. NFS alone does not satisfy this.
- [ ] Choose a storage method only after hardware-specific evidence, independent review, a verified recovery route and separate explicit owner risk approval. If those gates cannot be satisfied, keep the NAND write route blocked and document the honest limitation.
- [ ] Prove that installed software, device settings and a small test file survive two cold boots offline.

**Gate:** safe independent operation, actual persistence and documented rollback. The existing RAM-root boot does **not** meet this milestone.

## P3 — Usable standalone tablet fundamentals

- [ ] Confirm the core screen, touch, orientation, physical keys, Wi-Fi, basic audio, battery status and charging through repeatable hardware tests.
- [ ] Select the lightest viable user interaction stack from measurements; avoid desktop/UI work until P1 and P2 gates are resolved.
- [ ] Provide a practical settings and maintenance workflow without SSH or a laptop for normal use.
- [ ] Validate sleep/wake or document its limitations, power consumption, controlled shutdown and recovery.

**Gate:** usable day-to-day Linux without attached computer, clear limitations and no unobserved battery drain.

## P4 — Reproducibility, documentation and handoff

- [ ] Build from a clean clone on a second Linux computer with exact upstream/source provenance.
- [ ] Expand CI for release manifests, packaging, safety checks and non-hardware tests.
- [ ] Complete upstream licensing, security and sensitive-artifact review.
- [ ] Publish English installation, recovery, rollback and maintenance documentation.
- [ ] Release only after P1–P3 acceptance on physical hardware.

## P5 — Optional media and YouTube **(last, not release-blocking)**

This is **not a current development task**. Owner requirement: **at least 720p source-video playback**. No 240p/360p product target, no low-resolution fallback presented as success. The screen itself is 1024×768; a 1280×720 source may be scaled for display, but acceptable 720p decoding, audio sync, temperature and battery impact must be physically measured.

- [ ] Only after P0–P4, determine whether ≥720p lectures are viable on this exact hardware.
- [ ] If reliable 720p playback cannot be demonstrated, **drop YouTube/video support instead of forcing a lower-resolution solution**.
- [ ] If viable and separately approved, consider lawful media fetching, offline course content, subtitles and resume functionality.

**Priority lock:** charging → reliable boot → offline persistence → tablet fundamentals → handoff → optional ≥720p media. Do not start media work or NAND writing to bypass an earlier gate.
