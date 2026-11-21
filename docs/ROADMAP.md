# Roadmap and acceptance gates

All milestones require physical-device evidence and a reviewable PR before they are marked complete.

## P0 — Establish project baseline

- [x] First 32 GB iPad mini boots standalone Linux with Wi-Fi and SSH.
- [x] Capture current Alpine/RAM/GPU/audio/package baseline.
- [x] Document architecture, risks, upstream provenance and agent rules.
- [ ] Choose an original-code license compatible with any incorporated GPL-2.0 upstream components.
- [x] Rename the working repository to `LegacyPad-Linux` and keep it private during experimentation; public branding can be revisited before release.

## P1 — Reproducible RAM boot image + media playback **(next)**

- [ ] Audit the custom initramfs and PC-less packaging pipeline; preserve a known-good boot image and hashes.
- [ ] Host-only proof: bake one small, non-secret utility/default into a new RAM image and enforce iBEC size and RAM limits.
- [ ] Review rollback and obtain separate authorization before any on-iPad boot-image update.
- [ ] Confirm the utility survives **two cold boots**, one without Wi-Fi. This proves image repeatability, **not user-data persistence**.

- [ ] Refresh Alpine package index over Wi-Fi; record DNS, mirror and package availability.
- [ ] Inspect actual DRM devices, EGL stack and sound card.
- [ ] Estimate RAM/disk dependency footprint *before* attempting `mpv` installation.
- [ ] Play short audio-only sample with speakers; measure memory and CPU.
- [ ] Play 240p/360p low-complexity H.264 + AAC test clips, first via a temporary network stream, then from RAM if space permits.
- [ ] Record frame drops, audio sync, input responsiveness and battery cost.
- [ ] Decide: `mpv`/Wayland, a simpler direct-render option, or an audio-first product.

**Gates:** (A) verified repeatable RAM image with a known-good boot recovery path; (B) reproducible playback test with acceptable hardware measurements.

## P2 — Solve offline persistence

- [ ] Independently characterize the physical 32 GB NAND/FTL, including the 32 MiB LwVM chunks and previously divergent headers, **before considering writes**.
- [ ] Compare *safe* durable-storage options, including limitations of iOS Data encryption and unverified USB host mode.
- [ ] Pick one mechanism only after physical tests and explicit risk approval.
- [ ] Demonstrate content + progress surviving two cold boots, with Wi-Fi disabled.

**Gate:** no accidental iOS loss, persistent content, documented rollback.

## P3 — Touch-first interface

- [ ] Choose UI stack from the P1 measurements.
- [ ] Library, pause/seek, playback speed, subtitles, battery and network controls.
- [ ] Touch use without SSH or a laptop.

## P4 — Content preparation and synchronization

- [ ] Host content importer/transcoder for authorized educational media.
- [ ] Checksums, resume-safe transfers, course metadata, subtitles.
- [ ] Offline sync/restore tests; minimal human setup.

## P5 — Handoff quality

- [ ] Reproducible clean-room build on a second Linux computer.
- [ ] CI for manifest, packaging and non-hardware unit tests.
- [ ] Explicit security/licensing audit and maintainer guide.
- [ ] Release with known-good rollback, installation guide and limitations.

**Priority:** no new GUI framework, agent swarm or NAND flashing until P1 evidence exists. The original owner can delegate later using the stable evidence and acceptance criteria above.
