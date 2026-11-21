# Architecture — staged, offline-first

This document describes a **target architecture**, not a claim that the complete system works today.

## Layers

1. **Upstream hardware/boot:** Project Cascadia A5 kernel, GPU, firmware extraction, device tree and PC-less iBEC launcher. Preserve the exact upstream commit and any local deltas.
2. **Device base image:** Alpine armhf 3.24.x RAM Linux initially. A minimal boot profile provides touch input, Wi-Fi and recoverable SSH. The local image, not a desktop package manager, ultimately supplies reproducible essentials.
3. **Player:** Start with the Alpine `mpv` build (and its dependencies) to test ALSA and DRM/Wayland paths. If memory or rendering is inadequate, evaluate a smaller specialized SDL2/DRM player only **after** recording the failure.
4. **Library UI:** A lean touch-first shell to select lessons, resume position, control speed, show subtitles/transcripts, and access Wi-Fi/battery. Evaluate a small Wayland/labwc UI before writing a custom compositor; do not assume a browser is viable.
5. **Content pipeline on a PC:** Accept only content the user is authorized to obtain. Prepare an offline manifest, subtitle files and checksums. Transcode a conservative H.264/AAC 360p or lower test variant, plus an audio-only variant. Tune format with real hardware measurements.
6. **Synchronization:** A PC/server may download, transcode and sync when available, but no server may be required for playback away from home.
7. **Persistent media and state:** **Blocked pending safe hardware evidence.** The present RAM root loses installed packages, Wi-Fi settings, library metadata, bookmarks and video files on shutdown.

## Storage decision gate

| Candidate | Offline after reboot? | Current status |
| --- | --- | --- |
| RAM-only root | No | **Verified boot path**, volatile |
| Home NFS root | No, network/server required | Upstream supports it; unsuitable as final portable storage |
| iOS System filesystem | Small capacity; Linux read-only | System boot images already installed; not a viable multi-GB media library |
| iOS Data filesystem | Not validated | Upstream reports encrypted files and no Linux mount support; do not assume it can be read |
| Lightning USB host storage | Potentially | Upstream says USB host/VBUS support **not proven** on mini; test only with separate safe plan |
| Dedicated Linux NAND volume | Yes if working | **BLOCKED on this unverified 32 GB package**; no writes until compatibility and recovery evidence |

The project may demonstrate *network streaming* and playback **before** solving persistence, but it cannot be called a portable offline media product until the persistence gate passes.

## Media packaging concept

A host-side process eventually emits a package:

```text
lesson/
  manifest.json      # title, source, language, duration, codec, checksum
  media-360p.mp4     # H.264 + AAC, only if the device benchmark passes
  audio.m4a          # lower-power audio-first alternative
  subtitles.vtt      # optional, UTF-8
```

All outputs are treated as data, not executable code. Never store copyrighted lesson files or credentials in public Git.

## Performance budget

- Physical RAM: ~512 MB; Linux currently reports ~470 MiB visible.
- Retain a robust reserve for network, framebuffer, audio and recovery. Use measured peak RSS and available memory, not APK file download size, for player decisions.
- GPU rendering acceleration does **not** establish H.264 hardware decode.
- Initial codec test ladder: audio-only, 240p, 360p, 480p. Test 24/25/30 fps separately where meaningful.
- Record audio continuity, dropped frames, sustained CPU, memory, temperature/battery and responsiveness for a long lecture.

## Recovery and reproducibility

Keep the known-good iOS launcher and RAM Linux payload separately from experimental builds. A new build must preserve the ability to boot the existing known-good image; never overwrite the only recovery path as an unreviewed step. Record upstream source revision, local patch series, artifact hashes, verification method and how to restore the original launcher.
