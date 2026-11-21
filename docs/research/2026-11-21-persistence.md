# Persistence research: what survives reboot on a 32 GB iPad mini 1

Research date: **2026-11-21**. Status: **design investigation; no device changes authorized by this document**.

## Executive finding

The experimental device boots Linux 6.12 + Alpine 3.24.1 from `root=/dev/ram0`. That proves a PC-free Linux boot, **not** persistent storage. All live modifications to its RAM root disappear when power is lost. There are two independent requirements:

1. **Reproducible system**: the same applications, non-secret settings and UI are available on every boot.
2. **Persistent user state and media**: bookmarks, watch progress, downloaded lectures and user settings survive multiple power cycles away from home.

The first can be addressed without Linux NAND writes by building an immutable, curated image on the host and loading it via the existing iOS-side boot chain. The second still needs a proven writable storage path or a network service; an image rebuild is not a substitute for ongoing writable storage.

## Candidate mechanisms

| Mechanism | Applications after restart | User state / multi-GB videos after restart, offline | Assessment |
| --- | --- | --- | --- |
| Rebuild/pack selected apps and defaults into the RAM boot bundle | **Yes**, at the version baked into the image | **No** for newly created data | **Best next safe engineering milestone**, host-built; budget image size and RAM |
| Alpine diskless `lbu` / `apkovl` with a writable save medium | Yes when overlay + APK packages are restored from stable medium | Config only by default; actual videos need separate persistent storage | Useful **only if** a usable persistent medium is first provided |
| Download/reinstall applications into RAM at every boot | Only while network/mirrors are available | No | Slow and fragile; not a portable offline solution |
| iOS System HFS+ as an input for images | Existing boot images remain between restarts | Very small capacity; Linux read-only in upstream; user writes during Linux unavailable | **Existing successful boot path**, not the video library |
| iOS Data HFS+ | Not currently | Not currently | Upstream Linux cannot mount encrypted iOS Data user files |
| Home-PC NFS | Yes while connected to the host | Yes, but **not independent of home PC/network** | Useful for development and remote playback, not portable offline mode |
| Lightning USB storage | Potentially | Potentially | Not verified: upstream notes USB host power/VBUS issue; do not assume |
| Linux LwVM/ext4 NAND volume beside iOS | Yes | Yes | Upstream demonstrated this for its 16 GB device, **not yet validated on this physical 32 GB device** |
| Sync progress to a PC/server while online | On reconnect | No complete offline persistence | Possible optional backup, never the only record of offline progress |

## Why `lbu commit` does not solve it alone

The official Alpine diskless documentation says Alpine Local Backup requires a **writable medium** for changes to survive reboot. `apkovl` packages configurations, and a local APK cache can reinstall packages during the next boot. This is a viable approach for diskless systems that can read persistent media; it cannot save a file to itself when the only writable filesystem is RAM.

Our root is a project-specific **embedded initramfs**, not necessarily an unmodified Alpine diskless boot produced by `mkinitfs`. An off-the-shelf `lbu` workflow must not be assumed to integrate with the custom `init` without checking its restore mechanism.

Sources:
- [Alpine Wiki: Getting started, diskless/data modes](https://github.com/alpinelinux/alpine-wiki/blob/master/Getting-started.md)
- [Alpine Local Backup source](https://github.com/alpinelinux/alpine-conf/blob/master/lbu.in)
- [Alpine initramfs boot logic](https://github.com/alpinelinux/mkinitfs/blob/master/initramfs-init.in)

## Safe first milestone: durable system image without Linux NAND writes

**Proposed, not yet implemented/tested:**

1. Snapshot the last known-good local `staging-bundle.bin` and all six boot-file hashes on the host. Verify the existing iOS launcher can still boot it.
2. Enumerate the current initramfs build inputs and available RAM. Select **one very small application or non-secret default**, as a proof of image customization.
3. Install/cross-package that addition into the **build-time root tree on the host**, not the live iPad filesystem, then regenerate the bundled initramfs, staging image and PC-less `kernelcache`.
4. Check the upstream iBEC compressed-image size and memory-address limits **before transferring anything**. The PC-less research specifies uncompressed Mach-O constraints (`0x3f00000`) and a finite heap; package and RAM growth can break boot.
5. Run offline packer/verification tests and compare against the immutable known-good image. Only in a separately approved test may the iOS launcher be updated, with a genuine recoverable previous image.
6. Prove on physical hardware: cold boot A, executable present; cold boot B without Wi-Fi, executable still present; memory and boot time acceptable. Record `uname -a`, application version and hashes.
7. **Do not silently store passwords or private SSH keys** as defaults in a firmware image published to a repository or release.

Note: uploading a newly built `kernelcache` to the jailbroken **iOS System** partition *does write that partition through iOS*. “No Linux NAND writes” does **not** mean “no writes anywhere on the iPad.” Any update needs backup and rollback for the iOS-side boot files.

Primary upstream references:
- [PC-less iBEC chain, limits and System file paths](https://github.com/rzxvx/Project-Cascadia/blob/main/devices/a5/docs/research/p105-pcless-boot.md)
- [Project Cascadia Quickstart, NFS versus NAND](https://github.com/rzxvx/Project-Cascadia/blob/main/devices/a5/docs/QUICKSTART.md)

## Persistent videos and settings: the unresolved gate

A rebuildable system is worthwhile, but our intended learning library needs **gigabytes of writeable offline storage**; the current ~212 MiB iOS System free space *before* installing the ~34 MiB boot payload cannot serve that purpose. A filesystem present only under `/tmp` or `/dev/ram0` is lost. Upstream's Linux-side `ios mount` is read-only; it cannot save bookmarks or media to iOS System, and its Data partition remains encrypted.

For the near-term product proof:
- Test short streamed or RAM-staged, authorized audio/video clips and playback performance.
- Keep a canonical lesson catalog and progress ledger **on the host** while offline persistence is unresolved, clearly describing device-side state as temporary.
- Make progress metadata small, append-only and exportable; design for a later durable backend, but never claim offline completion until it survives real cold boots with no network.
- Do not add an HTTP/SSH write bridge back into iOS: iOS is no longer running after Linux starts.

## Distinct acceptance gates

**P1A: reproducible OS image** — application survives two cold boots, including one with Wi-Fi disabled; recovery to the known-good boot file set is documented.

**P1B: media engine** — actual speaker playback, tested codecs, max RSS, battery and frame drops are measured on hardware, not inferred from GPU support.

**P2: durable user data** — 1 GB+ test media and a position bookmark survive two power cycles, without an active host, with verified integrity and a safe recovery plan. This gate is **blocked**, especially for 32 GB NAND.

## Evidence limits

No live package or image experiment has been run as a result of this research. The existing screenshot showing `apk info` warnings only establishes that APK indexes were not cached, **not** that Wi-Fi, DNS or HTTPS is broken. The image-embedding proposal is an engineering inference based on the documented boot bundle; physical performance and boot success require tests.
