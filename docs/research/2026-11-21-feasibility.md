# Feasibility review — 2026-11-21

## Scope and source pin

Independent first-pass review for **LegacyPad Linux**. The upstream reference is [Project Cascadia commit `ad28ba40ba6f2a1d244ab51b637ceb31155fa126`](https://github.com/rzxvx/Project-Cascadia/commit/ad28ba40ba6f2a1d244ab51b637ceb31155fa126), dated 2026-11-19. Upstream evolves rapidly; changes after this pin require a separate review.

## Evidence matrix

| Question | Source or observation | Assessment |
| --- | --- | --- |
| Can Linux boot without PC? | Physical 32 GB iPad: iOS-side patched iBEC -> kernel -> `p105ap:~#` | **Proven on this unit** |
| Can we control it over WLAN? | Physical iPad connected and accepted authenticated G570 SSH session | **Proven on this unit** |
| Are GPU, display and audio drivers possible? | `/dev/fb0`, `/dev/dri`, `/dev/snd` on device; upstream A5 reports SGX/Mesa and ALSA | **Nodes proven; applications not** |
| Is a video player packaged for the CPU? | [Alpine 3.24 armhf `mpv`](https://pkgs.alpinelinux.org/package/v3.24/community/armhf/mpv) | **Package exists**; large dependency set; runtime untested |
| Can the device decode H.264 video smoothly? | No physical playback benchmark or demonstrated hardware video decoder | **Unknown** |
| Is a light Wayland desktop possible? | [Upstream labwc setup](https://github.com/rzxvx/Project-Cascadia/blob/ad28ba40ba6f2a1d244ab51b637ceb31155fa126/devices/a5/tools/desktop/labwc/labwc-setup.sh) | **Upstream demonstrated**; dependency/RAM cost here unknown |
| Does the iOS Data partition hold accessible Linux videos? | [Upstream A5 storage section](https://github.com/rzxvx/Project-Cascadia/blob/ad28ba40ba6f2a1d244ab51b637ceb31155fa126/devices/a5/README.md#where-linux-keeps-its-files) | **No**: encrypted Data files are not mounted by current upstream approach |
| Is USB flash storage ready? | [Upstream A5 USB host section](https://github.com/rzxvx/Project-Cascadia/blob/ad28ba40ba6f2a1d244ab51b637ceb31155fa126/devices/a5/README.md#a-usb-flash-drive) | **No**: VBUS/host work not proven |
| Can we safely use this 32 GB internal NAND as Linux storage? | Prior 32 GB NAND diagnostics, local header mismatch, physical package not verified | **Blocked** |
| Do `apk info` cache warnings prove repositories unavailable? | Cached APKINDEX missing from fresh volatile root | **No conclusion**; run network and `apk update` checks |

## Direct upstream references

1. [Project Cascadia A5 device status](https://github.com/rzxvx/Project-Cascadia/blob/ad28ba40ba6f2a1d244ab51b637ceb31155fa126/devices/a5/README.md) — PC-less boot, GPU, audio, storage and important restrictions.
2. [PC-less boot-chain research](https://github.com/rzxvx/Project-Cascadia/blob/ad28ba40ba6f2a1d244ab51b637ceb31155fa126/devices/a5/docs/research/p105-pcless-boot.md) — custom iBEC, System HFS+, compressed bundle and memory/address constraints.
3. [A5 audio reverse-engineering](https://github.com/rzxvx/Project-Cascadia/blob/ad28ba40ba6f2a1d244ab51b637ceb31155fa126/devices/a5/docs/research/p105-audio.md) — speaker support through ALSA.
4. [A5 labwc setup](https://github.com/rzxvx/Project-Cascadia/blob/ad28ba40ba6f2a1d244ab51b637ceb31155fa126/devices/a5/tools/desktop/labwc/labwc-setup.sh) — GPU compositor and touch interface.
5. [Alpine 3.24 `mpv` package for armhf](https://pkgs.alpinelinux.org/package/v3.24/community/armhf/mpv) — packaged player and 50 runtime library dependencies; package install size alone understates the dependency footprint.
6. [mpv manual](https://mpv.io/manual/master/) — playback options, output backends, speed, resume and performance statistics.

## Recommendation

1. **First prove audible, smooth playback** using a small authorized test file and a measured system baseline. Do not start with a complete XFCE/browser installation.
2. Use the available host PC to transcode candidate 240p/360p H.264 Baseline/AAC files and audio-only versions; do not rely on unverified hardware video decode.
3. Compare light UI paths only once the player's actual RAM/CPU/rendering needs are known.
4. Keep the persistence blocker visible: NFS-only streaming is a test tool, not a portable-offline product.
5. Track all physical test logs separately from theoretical and local tests, with private data redacted.

## Known issue: APKINDEX warnings

A fresh RAM boot showed:
- Alpine `3.24.1`.
- Installed tool count returned by `apk info`.
- `WARNING: opening from cache .../APKINDEX.tar.gz: No such file or directory`.

The missing *local cache* is the direct observation. It does not prove that the Alpine package endpoint is inaccessible or that installing `mpv` will work. The correct next diagnostic is a bounded network/DNS check and `apk update` on the running RAM root, followed by a dependency estimate. Avoid switching Alpine branches or changing repositories before that evidence.

## Risks still open

- Real thermal, charge and battery behavior under media decode.
- Whether `mpv` supports a suitable DRM/KMS/Wayland output combination with Cascadia's Mesa build.
- Software decoder speed on dual-core A5 versus lecture resolution/frame rate.
- Gigabyte-scale safe storage that survives power-off.
- Startup and Wi-Fi credential persistence without a separate computer.

No media performance claims should be published until measured on the physical device.
