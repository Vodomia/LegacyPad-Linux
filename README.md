# LegacyPad Linux

**A lightweight, offline-first learning hub for legacy tablets.**

The first target is the **Apple iPad mini (1st generation, A1432 / iPad2,5 / p105ap)**. The long-term goal is a portable reading, audio, and educational-video device with a touch-friendly interface, offline lessons, subtitles, bookmarks, and reliable battery life.

> **Experimental / not yet a finished media player.** A real 32 GB iPad mini has booted Linux 6.12 with an Alpine 3.24.1 RAM root, Wi-Fi, touch keyboard, audio device nodes, GPU device nodes, and SSH access. **Video playback, media persistence, and the product UI are not yet validated.**

## Goals

- Play locally available educational videos and long lectures, eventually without a PC or home network.
- Work within the device's approximately 512 MB physical RAM; favor audio-first and low-resolution video.
- Remain reproducible, inspectable, and transferable to new maintainers or a future company team.
- Keep low-level boot research separate from the user-facing application and media pipeline.
- Prefer free software and an incremental, measurable approach.

## Current machine

| Item | Observed state |
| --- | --- |
| Hardware | iPad mini 1, 32 GB NAND, A5, iPad2,5 / p105ap |
| iOS | 8.4.1 (12H321), jailbroken; retained as boot launcher |
| Linux | Cascadia-derived 6.12 kernel, Alpine 3.24.1 RAM-based root |
| Access | Standalone boot from iOS; Wi-Fi and SSH verified |
| RAM | 470 MiB visible; ~404 MiB available at idle |
| Display / GPU / audio | `/dev/fb0`, `/dev/dri`, `/dev/snd` exist; no performance benchmark yet |
| Video players | `mpv`, `ffmpeg`, `labwc`, `weston` absent in current RAM image; `aplay` available |
| Durable Linux storage | **Not available in the current RAM boot** |

The present device runs Linux without any cable after triggering the boot from iOS. This does **not** yet mean that lesson files are available offline under Linux.

## Repository layout

- [Project charter](docs/PROJECT_CHARTER.md): target users, goals, MVP, boundaries.
- [Verified baseline](docs/HARDWARE_BASELINE.md): observations vs. upstream claims.
- [Architecture](docs/ARCHITECTURE.md): boot, media, UI, synchronization and storage gates.
- [Roadmap](docs/ROADMAP.md): measurable milestones.
- [Research](docs/research/2026-11-21-feasibility.md): feasibility sources and open questions.
- [Actual 32 GB device bring-up](docs/bringup/2026-11-21-32gb-pcless-ram-linux.md): the PC-less RAM Linux installation, incidents and observed outcome.
- [32 GB NAND investigation](docs/research/2026-11-21-p105-32gb-nand.md): independent dynamic LwVM evidence, the unresolved FTL gate, and prior-art search.
- [Reboot persistence research](docs/research/2026-11-21-persistence.md): reproducible system images vs. durable media/settings.
- [Gemini engineering handoff](docs/handoffs/GEMINI-PERSISTENCE-32GB-AUDIT.md): bounded, host-first research instructions.
- [Safety decision](docs/decisions/ADR-0001-ram-first.md): why NAND writing is blocked for this device.
- [Agent rules](AGENTS.md): requirements for AI-assisted contributions.

## Provenance and licensing

This project builds on the research of [Project Cascadia](https://github.com/rzxvx/Project-Cascadia) (GPL-2.0). Its hardware support, kernel, boot tooling, and GPU stack belong to that upstream effort and its contributors. No Apple firmware or existing Cascadia build artifacts are included here.

**The license for original LegacyPad Linux code has not yet been chosen.** Before importing or distributing upstream-derived source/binaries, review GPL obligations and third-party licenses. Do not copy an existing local modified Cascadia tree into this repository without a provenance and license audit.

## Safety

The physical 32 GB NAND/FTL variant has **not** been verified safe for repartitioning or Linux writes. Do not run NAND installation, flash writes, partition changes, or destructive cleanup as a routine development step. Use non-destructive, RAM-root experiments until a separate validated storage decision is approved.

The repository is currently **private**, with potential public release later. Never commit passwords, SSH private keys, Wi-Fi credentials, device identifiers, user-specific local network addresses, firmware blobs, raw NAND dumps, or proprietary videos.

## Status

See [Roadmap](docs/ROADMAP.md). The immediate next task is a **measured audio/video playback proof of concept**, not a full desktop installation.
