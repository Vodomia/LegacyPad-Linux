# Physical device baseline

Last confirmed: **2026-11-21**, user-provided on-device terminal and SSH screenshots.

## Verified on this 32 GB unit

| Observation | Evidence / command | Result |
| --- | --- | --- |
| Board | iOS `sysctl -n hw.machine` | `iPad2,5` |
| iOS build | iOS `sysctl -n kern.osversion` | `12H321` (iOS 8.4.1) |
| Standalone boot | iOS-side `linux` launcher, patched iBEC, Linux shell on glass | **PASS**; no PC cable during Linux runtime |
| Linux network | `wifi connect`, remote SSH on WLAN | **PASS** |
| Linux release | `cat /etc/alpine-release` | `3.24.1` |
| Physical memory visible to Linux | `free -m` | 470 MiB total; 20 MiB used; ~404 MiB available at idle |
| Current root persistence | `df -h` and build bootargs | RAM root `root=/dev/ram0`; no durable media volume reported |
| Framebuffer | `ls -ld /dev/fb0` | Present |
| DRM/GPU device directory | `ls -ld /dev/dri` | Present; real rendering performance untested |
| ALSA device directory | `ls -ld /dev/snd` | Present; `aplay` executable available |
| Player tools | `command -v` | `mpv`, `ffmpeg`, `weston`, `labwc` absent |
| Package index state | `apk info` | 16 installed entries printed; missing cached `APKINDEX.tar.gz` warnings |

The cached `APKINDEX` warnings do **not**, by themselves, establish a DNS outage or server incompatibility. A network check and `apk update` are needed before choosing a remedy.

## Reported by upstream, not yet validated here

The [Project Cascadia A5 README](https://github.com/rzxvx/Project-Cascadia/blob/ad28ba40ba6f2a1d244ab51b637ceb31155fa126/devices/a5/README.md) reports:
- GPU accelerated Wayland labwc desktop via its SGX543/Mesa work.
- ALSA speakers, touch and Wi-Fi support.
- iOS System read-only access; iOS Data is file-encrypted and unavailable through the present Linux mount.
- NAND-backed Linux support tested upstream, with hardware and FTL risks.

**None of the upstream playback or NAND claims substitutes for tests on this specific 32 GB physical package.**

## Open technical questions

1. Which DRM device nodes (`card0`, `renderD128`, etc.) and usable EGL driver are actually available?
2. Does `apk update` work over the present WLAN and how much memory does `mpv` plus dependencies require?
3. Does ALSA speaker playback succeed on this unit?
4. Can software decoding sustain 360p H.264 + AAC, with subtitles and acceptable heat/battery usage?
5. Can one safe persistent storage mechanism support gigabytes of lessons and survive reboot?
6. Can the full standalone workflow start from the iPad's own touch UI without a G570?

## Next non-destructive checks

From a working SSH shell *on the iPad*, with Wi-Fi connected:

```sh
ip route
cat /etc/apk/repositories
apk update
apk policy mpv ffmpeg
aplay -l
ls -l /dev/dri /dev/snd
free -m
```

These commands inspect network/package/device state and refresh the **RAM-resident** package index. They do not flash or partition NAND. Record only sanitized outputs (no private IPs, SSIDs or secrets). Do **not** execute `apk add`, a media benchmark, or any storage writes as part of this check.
