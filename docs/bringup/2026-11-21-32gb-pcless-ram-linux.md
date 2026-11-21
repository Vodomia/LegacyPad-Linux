# Field report: PC-less RAM Linux on a 32 GB iPad mini 1

**Field date:** 2026-11-21  
**Result:** **PASS — Linux boots on-device with no host cable**, from a jailbroken iOS command.  
**Scope:** A reproducible incident and provenance record, **not** a redistributable firmware image and **not** a NAND-backed Linux installation.

## Device and starting point

- **Hardware:** first-generation Wi-Fi iPad mini, A1432 / `iPad2,5` / `p105ap`, Apple A5, **32 GB-class NAND**.
- **iOS:** jailbroken 8.4.1, build `12H321`; OpenSSH installed.
- **Build host:** Linux Mint on a Lenovo G570; the local working checkout is a derivative of [rzxvx/Project-Cascadia](https://github.com/rzxvx/Project-Cascadia). Original iOS 8.4.1 firmware was supplied locally to produce device-compatible boot images.
- **Target OS:** Linux 6.12, Alpine armhf 3.24.1, embedded RAM root. Startup command line includes `root=/dev/ram0`.
- **Persistent Linux root:** **none**. No new Linux LwVM partition was created.

Cascadia's upstream [PC-less research](https://github.com/rzxvx/Project-Cascadia/blob/main/devices/a5/docs/research/p105-pcless-boot.md) documents the core iOS -> kloader -> patched iBEC -> kernelcache mechanism. Our local `devices/a5/tools/p105-pcless.sh` is additional integration/rollback work by Gemini **not yet imported or reviewed in this repository**.

## What actually boots

```text
jailbroken iOS 8.4.1
  -> on-device root command: linux
  -> kloader starts an iBEC.upgrade image built for 12H321
  -> iBEC mounts the existing iOS System HFS+ partition
  -> devicetree + ramdisk placeholder + kernelcache (at System root)
  -> Cascadia boot bundle -> Linux 6.12 -> Alpine RAM root
  -> framebuffer shell and on-screen touch keyboard
  -> Wi-Fi / SSH, with no host cable required
```

**Important persistence distinction:** these *boot images* stay on the jailbroken iOS System filesystem across iPad restarts. Linux's runtime filesystem does **not**; `apk add`, RAM files and most live configuration edits vanish after power-off. The user enters iOS and starts Linux again; this is not automatic power-on directly into Linux.

## Boot-file placement

The locally built `p105-pcless.sh` installer transferred **six** verified artifacts through jailbroken iOS/OpenSSH:

| Path on iOS System | Artifact | Size observed |
| --- | --- | ---: |
| `/kernelcache` | Linux staging bundle wrapped as iBEC-compatible img3 | 33,587,612 bytes |
| `/ramdisk` | img3 placeholder required by iBEC | 4,188 bytes |
| `/devicetree` | iOS 12H321-compatible device tree img3 | 79,328 bytes |
| `/usr/local/cascadia/kloader` | Local pinned legacy loader | 52,064 bytes |
| `/usr/local/cascadia/iBEC.upgrade` | Locally patched iBEC | 282,624 bytes |
| `/usr/bin/linux` | Local iOS-side launcher script | 801 bytes |

These paths are on the **System partition as seen from iOS**, not paths in the Linux root. The loader uses iBEC's iOS-side HFS+ read path to access them. The iOS System partition had `217276` KiB of free space during preflight, before transferring the roughly 34 MiB payload.

The PC-less image build reported the inner bundle at **29,851,136 bytes**. The offline C verifier:
- unwrapped img3/complzss to that exact bundle;
- extracted/reassembled the platform layer;
- rewrapped the same `kernelcache` **bit for bit**;
- verified the relevant bootargs lacked Linux NAND write enables.

The iBEC upgrade patch adapts its upgrade logic to load from **System** (replacing the `Update` partition literal), forces the upgrade boot path and suppresses NVRAM save/record operations. Exact offsets and constraints belong to the [upstream research](https://github.com/rzxvx/Project-Cascadia/blob/main/devices/a5/docs/research/p105-pcless-boot.md) and the local modified source.

## Installation actually performed

1. Download/build prerequisites, 12H321 firmware-derived images and the custom PC-less scripts were prepared **on the host**. Upstream source and local patch provenance need to be preserved before anyone can reproduce this from a fresh clone.
2. `p105-pcless.sh verify`: local C round-trip, iBEC patch tests and bootargs/PPN write-gate checks **passed**. Local 32 GB LwVM tests also passed offline but have no bearing on actual NAND writer safety.
3. `p105-pcless.sh check-ios`: SSH to jailbroken iOS; `hw.machine=iPad2,5`, `kern.osversion=12H321`, `df -k /` -> `217276` KiB free. The six target files were absent.
4. **First install attempt failed:** after all six staged files uploaded and SHA-1 matched, the activation script called `basename`, which was **not present** on the device's minimal iOS shell. The installer reported rollback.
5. Gemini revised generated remote shell code (POSIX `${path##*/}`, no external `basename`, correct variable expansion), added a manifest-aware rollback and simulated failures on host. Local tests passed. Any software-level rollback claim does not eliminate the separate low-level device risk.
6. After confirming no active files/manifest remained, the owner removed only stale `.new` staging artifacts on iOS and repeated `IOS_HOST=<private-ip> ./devices/a5/tools/p105-pcless.sh install`.
7. **Successful installation:** six staged uploads, local and remote SHA-1/size checks, activation with a backup manifest, and `sync; sleep 40; sync` succeeded. The host printed **INSTALLATION COMPLETE AND VERIFIED**.
8. On the iPad, the user ran `linux` with root privileges in an iOS terminal, then pressed **Home once** after the screen turned black. The iPad booted Linux and presented `p105ap:~#`.

**Do not run the upstream NAND installer as a substitute** for this PC-less RAM method. The upstream normal `./cascadia a5 install` offers to rewrite a NAND partition table, and this 32 GB hardware has not passed that safety gate.

## Verified outcome on the iPad

| Observation | Outcome |
| --- | --- |
| Linux shell on touch screen | **PASS**; framebuffer touch keyboard |
| Boot without host/cable | **PASS**, initiated on iOS |
| Linux version | 6.12 family, custom Cascadia derivative |
| Alpine release | `3.24.1` |
| RAM | `free -m`: 470 MiB total, ~404 MiB available at idle |
| Wi-Fi | Connected and acquired a local-network IPv4 address |
| SSH | Linux device accepted host connection after fixing home-directory ownership |
| ALSA / GPU | `/dev/snd`, `/dev/dri`, `/dev/fb0` present; real media benchmarking outstanding |
| Root storage | `df -h`: devtmpfs/tmpfs and a small `/run/rescue` tmpfs; **no Linux NAND volume** |
| User applications | `mpv`, `ffmpeg`, `weston`, `labwc` not present; `aplay` present |

### SSH incident and recovery

Dropbear rejected incoming sessions with “`/root must be owned by user or root, and not writable by group or others`”. The directory had accidentally been assigned numeric owner **700** when a `chown` command was mistyped. It was restored to UID/GID **0:0** and owner-only permissions, after which SSH worked. Avoid blind permission scripts; record before/after owner and mode.

## Why this path was chosen for the 32 GB unit

The original NAND install reported inconsistent dual LwVM header copies because its **16 GB** code read the supposed backup at LBA 4095. A subsequent **local snapshot audit** found matching primary and backup headers at LBA 0 and the correct **32 GB** backup LBA 8191; the older error was likely a false alarm. Other code still expected **16 billion** media bytes and rejected the observed **32 billion**. Gemini's dynamic-media changes and offline tests were **not** a hardware-proven NAND-writer fix. Rather than initiate further FTL/partition writes, the project switched to a RAM Linux root with a durable **boot payload on iOS System**. See [the 32 GB NAND investigation](../research/2026-11-21-p105-32gb-nand.md).

**Correction for future reports:** saying this process “never writes NAND” is inaccurate. Uploading the six iOS System files **writes NAND via iOS**. The narrower and verified claim is that the resulting Linux root runs in RAM and its bootargs/driver setup do not intentionally write a Linux NAND volume.

## Reproduction and release blockers

The current repository does not yet contain:
- the local `p105-pcless.sh` and its helper tools/tests as a reviewed patch series;
- exact base commit, differential patch series and third-party license analysis;
- reproducible host build, pinned inputs and SHA-256 manifests for the *non-redistributable* local artifacts;
- a documented hardware restore exercise for the iOS-side launcher.

It therefore records a **successful field result**, **not yet a fully reproducible public install**. Gemini should prepare a source-only import as a separate PR; reject private SSH keys, host-specific addresses, raw NAND dumps and Apple firmware binaries. Any app installation or custom boot image update must preserve and verify the previous known-good set.

## Primary sources

- [Project Cascadia A5 README](https://github.com/rzxvx/Project-Cascadia/blob/main/devices/a5/README.md)
- [PC-less iBEC boot design](https://github.com/rzxvx/Project-Cascadia/blob/main/devices/a5/docs/research/p105-pcless-boot.md)
- [A5 Quickstart and NAND warnings](https://github.com/rzxvx/Project-Cascadia/blob/main/devices/a5/docs/QUICKSTART.md)
- [Persistence research](../research/2026-11-21-persistence.md)
