# Building & Verifying LegacyPad-Linux Candidate RAM Linux Images

**Target Device:** Apple iPad mini 1 (`iPad2,5` / A1432 / P105AP, Apple S5L8942X SoC, 32 GB NAND)  
**Host Firmware:** Apple iOS 8.4.1 (Build `12H321`)  
**License:** GPL-2.0-only (see [`LICENSE`](LICENSE))  
**Attribution:** Derived from [Project Cascadia](https://github.com/rzxvx/Project-Cascadia) (base commit `ad28ba40ba6f2a1d244ab51b637ceb31155fa126`) for [LegacyPad-Linux](https://github.com/Vodomia/LegacyPad-Linux).

---

## 1. Overview & Architectural Principles

This document provides complete instructions to reproduce and verify the candidate PC-less RAM Linux boot image from source on an x86_64 or aarch64 Linux host.

### Storage & Runtime Operational Distinction
It is critical to distinguish host-side preparatory writes from runtime Linux behavior:
1. **Preparatory Installation Writes to iOS System Partition:**  
   Transferring the bootchain files (`/kernelcache`, `/ramdisk`, `/devicetree`, `/usr/local/cascadia/*`, `/usr/bin/linux`) writes directly to the iPad's iOS System partition (HFS+ volume on NAND).
2. **Volatile RAM Rootfs at Runtime (`/dev/ram0`):**  
   Once kloader transfers control to patched `iBEC.upgrade`, the kernel unpacks into system memory. All Linux userland operations run exclusively in RAM on `/dev/ram0`.
3. **Hardware Write Protection at Runtime:**  
   Kernel bootargs strictly omit write flags (`apple_ppn.allow_write=1`, `apple_ftl.enable_write=1`, `apple_ftl.write_volume` absent) and the PPN hardware node is absent from the RAM device tree.
4. **Standalone Operation:**  
   After the iOS trigger (`linux`), Linux runs independently with zero runtime dependency on USB cables, Macs, or NFS servers.

---

## 2. Prerequisites & Environment

### 2.1 Host Operating System & Packages
Standard Linux host (Debian, Ubuntu, Linux Mint, Fedora, Arch):
- `gcc` and `make` (Host build tools)
- `arm-linux-gnueabihf-gcc` and `arm-linux-gnueabihf-objcopy` (ARMv7 cross-toolchain)
- `python3` (>= 3.8)
- Standard core utilities: `bash`, `dash` (or `/bin/sh`), `stat`, `dd`, `cat`, `sha256sum`, `unzip`

```bash
# On Debian / Ubuntu / Linux Mint:
sudo apt-get update
sudo apt-get install -y build-essential gcc-arm-linux-gnueabihf python3
```

### 2.2 Upstream Project Cascadia Integration & Fresh Clone Setup
LegacyPad-Linux builds upon upstream [Project Cascadia](https://github.com/rzxvx/Project-Cascadia) (base commit `ad28ba40ba6f2a1d244ab51b637ceb31155fa126`), adding PMU charging recovery, pure sysfs power telemetry, dynamic 32 GB LwVM scaling, and atomic PC-less bootloader management.

To reproduce candidate images from a fresh clone:
1. **Clone upstream and fork repositories:**
   ```bash
   git clone https://github.com/rzxvx/Project-Cascadia.git
   git clone https://github.com/Vodomia/LegacyPad-Linux.git
   cd Project-Cascadia
   git checkout ad28ba40ba6f2a1d244ab51b637ceb31155fa126
   export CASCADIA_ROOT="$(pwd)"
   ```

2. **Integrate LegacyPad enhancements into the Cascadia tree:**
   ```bash
   # Copy PMU charger driver source
   cp ../LegacyPad-Linux/devices/a5/patches/files/drivers/power/supply/apple-pmu-charger.c \
      "$CASCADIA_ROOT/devices/a5/patches/files/drivers/power/supply/apple-pmu-charger.c"

   # Copy rootfs overlay utilities
   mkdir -p "$CASCADIA_ROOT/devices/a5/overlay"
   cp -a ../LegacyPad-Linux/devices/a5/overlay/. "$CASCADIA_ROOT/devices/a5/overlay/"

   # Copy LwVM dynamic storage tools and installer
   cp ../LegacyPad-Linux/devices/a5/tools/nand-volume/lwvm.py "$CASCADIA_ROOT/devices/a5/tools/nand-volume/lwvm.py"
   cp ../LegacyPad-Linux/devices/a5/tools/p105-pcless.sh "$CASCADIA_ROOT/devices/a5/tools/p105-pcless.sh"
   ```
   *(Alternatively, apply the cumulative patch: `git apply ../LegacyPad-Linux/0000-all-candidate-ram-and-pmu-changes.patch`)*

### 2.3 Proprietary Firmware Inputs (NOT in git repository)
In compliance with Apple copyright terms and open-source licensing, proprietary binaries are **never** committed to this repository. The user must provide the official Apple IPSW:
- **IPSW File:** `iPad2,5_8.4.1_12H321_Restore.ipsw` (MD5: `53f1d33cb8e11a141c22b102ce57eeea`)
- **Extracted iBEC:** `Firmware/dfu/iBEC.p105ap.RELEASE.dfu` (decrypted to `iBEC.dec` and signature-patched to `iBEC.patched`)
- **Extracted DeviceTree:** `Firmware/all_flash/all_flash.p105ap.production/DeviceTree.p105ap.img3` (decrypted to `DeviceTree.dec`)
- **kloader binary:** SHA-256 `bec212b4d99a1e3b9fa4add663fa884a2435045d1e47051415f4e26e197f8132`

---

## 3. Step-by-Step Reproduction Guide

### Step 1: Prepare the Custom Overlay
The RAM filesystem overlay in `devices/a5/overlay/` accommodates custom runtime utilities unpacked by the kernel at boot over the base initramfs.
The diagnostic utilities [`legacypad-status`](devices/a5/overlay/usr/bin/legacypad-status) and [`legacypad-power`](devices/a5/overlay/usr/bin/legacypad-power) are tracked directly in this repository:
```bash
chmod +x devices/a5/overlay/usr/bin/legacypad-status
chmod +x devices/a5/overlay/usr/bin/legacypad-power
```

### Step 2: Assemble the Candidate Boot Bundle
Run `assemble.py` from Project Cascadia with the complete build overlay (including hardware firmware and LegacyPad-Linux utilities):
```bash
python3 "$CASCADIA_ROOT/devices/a5/scripts/assemble.py" \
    "$CASCADIA_ROOT/devices/a5/output/linux-boot.bin" \
    "$CASCADIA_ROOT/devices/a5/output/candidate-zImage-dtb" \
    "$CASCADIA_ROOT/devices/a5/build/overlay" \
    "$CASCADIA_ROOT/devices/a5/output/candidate-staging-bundle.bin"
```
- **Loader:** Starts at `0x80000000`, padded to `0x8000` (32 KiB).
- **Kernel (`candidate-zImage-dtb`):** Located at `0x80008000`.
- **Overlay:** Packed as a `newc` CPIO archive starting at offset `0x1b55000` (1,207,296 bytes).

### Step 3: Patch iBEC for System Root Boot (`iBEC.upgrade`)
Apply PC-less patches to the decrypted iBEC using `patch-ibec-upgrade.py`:
```bash
python3 "$CASCADIA_ROOT/devices/a5/scripts/patch-ibec-upgrade.py" \
    "$CASCADIA_ROOT/devices/a5/build/firmware/iBEC.patched" \
    "$CASCADIA_ROOT/devices/a5/build/p105/pcless-candidate/iBEC.upgrade"
```
- Bypasses NVRAM auto-boot checks (`auto-boot=true`).
- Sets default boot command to `upgrade`.
- Points the OTA mount target from partition `Update` to `System` (read-only HFS+).
- Removes NVRAM `saveenv()` calls to prevent any persistent wear or alteration of NVRAM.

### Step 4: Wrap Mach-O, Compress LZSS, and Pack IMG3 (`make-pcless.py`)
Package the candidate bundle into Apple img3 containers:
```bash
python3 "$CASCADIA_ROOT/devices/a5/scripts/make-pcless.py" \
    --board p105 \
    --ipsw "$IPSW_PATH" \
    --bundle "$CASCADIA_ROOT/devices/a5/output/candidate-staging-bundle.bin" \
    --devicetree "$CASCADIA_ROOT/devices/a5/build/firmware/DeviceTree.dec" \
    --out "$CASCADIA_ROOT/devices/a5/build/p105/pcless-candidate"
```
Generates candidate artifacts: `kernelcache`, `ramdisk`, `devicetree`.

---

## 4. Host-Side Verification Suite

All verification tests are strictly offline and run on the host system without device communication.

### 4.1 C Round-Trip Verifier (`test-pcless.c`)
Compile and run the native C round-trip verifier:
```bash
gcc -Wall -Wextra -O2 -I"$CASCADIA_ROOT/devices/a5/app" -o /tmp/test-pcless \
    "$CASCADIA_ROOT/devices/a5/tests/test-pcless.c" "$CASCADIA_ROOT/devices/a5/app/pcless.c"

/tmp/test-pcless \
    "$CASCADIA_ROOT/devices/a5/build/p105/pcless-candidate/kernelcache" \
    "$CASCADIA_ROOT/devices/a5/output/candidate-staging-bundle.bin" \
    "$CASCADIA_ROOT/devices/a5/output/linux-boot.bin" \
    "$CASCADIA_ROOT/devices/a5/output/candidate-zImage-dtb"
```
Expected output:
```text
ok   unwrap(kernelcache) == bundle (29867008 bytes)
     layer at 0x1b55000, 1207296 bytes
ok   assemble(loader, zImage-dtb, layer) == bundle (29867008 bytes)
ok   wrap(bundle) == kernelcache (33605468 bytes)
PASS
```

### 4.2 Installer Atomic Rollback & Update Test Harness (`test-pcless-rollback.sh`)
Execute the simulated POSIX `/bin/sh` installer test suite (11/11 scenarios):
```bash
./devices/a5/tests/test-pcless-rollback.sh
```
Tests:
1. Clean initial installation across all 6 targets.
2. Protection in install-only mode against overwriting initial backups.
3. Safe update mode: updates active files, saves to `previous/`, preserves `.orig`.
4. Failure during update: cleanly restores previous active files, leaves `.orig` intact.
5. Dedicated rollback command: restores files from `previous/`.
6. Remove with missing manifest: strictly refuses to delete active files.
7. Manifest-based clean remove: cleanly restores pre-existing files & deletes Cascadia files.
8. Failure during manifest/backup creation: zero partial manifest or `.new` files left.
9. Failure at 4th file with empty initial state: complete clean rollback.
10. Failure at 4th file with pre-existing canary files: 100% bit-for-bit restoration.
11. Candidate `OUT` selection: confirms `OUT` variable is preserved and not overridden.

### 4.3 Standalone LwVM Dynamic Capacity Test Suite (`test_lwvm_dynamic.py`)
Run the dynamic chunk geometry tests (self-contained with [`lwvm.py`](devices/a5/tools/nand-volume/lwvm.py)):
```bash
python3 -m unittest devices/a5/tools/nand-volume/test_lwvm_dynamic.py
```
Validates:
- 16 GB legacy partition geometry regression.
- 32 GB chunk scaling (32 MiB chunk size).
- Bit-for-bit identity between LBA 0 primary and LBA 8191 backup headers.
- Rejection of invalid magic, corrupted CRC-32, slice overflows, and partition overlaps.

---

## 5. Artifact Manifest & Checksum Comparison

### 5.1 Known-Good Baseline Manifest
Preserved untouched in `devices/a5/build/p105/pcless-known-good/`:

| Artifact | Size (Bytes) | SHA-256 Checksum |
| :--- | ---: | :--- |
| `kernelcache` | 33,587,612 | `5ab87f2c6056fcd056d92ab5e24034803d4458d6a80ba59b178b21f7816c6967` |
| `ramdisk` | 4,188 | `22459577003a9dbd6e92c132371e321098044e711b507709ad09b09176008dd8` |
| `devicetree` | 79,328 | `9abf1a5f73a824bf2652909ec24584ecaff09c725bbea80bfa20b833ccf6b6dd` |
| `iBEC.upgrade` | 282,624 | `ede34b70bf7f8a7f819f1e6a96c94f4f0ecc2c060af4dfe61ffe7a363f7865ef` |
| `linux` | 801 | `d0edb18aae8cf681cac8a2551348a40f70c6fb2b4753bff314899f5890efbafe` |
| `staging-bundle.bin` | 29,851,136 | `90794c21d0f976047177d051b5175e28a722bc225894bb5700714700590a7a3f` |

### 5.2 Candidate Manifest (`pcless-candidate`)
Built in `devices/a5/build/p105/pcless-candidate/`:

| Artifact | Size (Bytes) | SHA-256 Checksum | Delta vs. Baseline |
| :--- | ---: | :--- | ---: |
| `kernelcache` | 33,605,468 | `8e1cc0d7143142040c7dabbc7a6b4d156b76f3f99cb7640a676505f0f3dfcf87` | +17,856 bytes |
| `ramdisk` | 4,188 | `22459577003a9dbd6e92c132371e321098044e711b507709ad09b09176008dd8` | 0 (Identical) |
| `devicetree` | 79,328 | `9abf1a5f73a824bf2652909ec24584ecaff09c725bbea80bfa20b833ccf6b6dd` | 0 (Identical) |
| `iBEC.upgrade` | 282,624 | `ede34b70bf7f8a7f819f1e6a96c94f4f0ecc2c060af4dfe61ffe7a363f7865ef` | 0 (Identical) |
| `linux` | 801 | `d0edb18aae8cf681cac8a2551348a40f70c6fb2b4753bff314899f5890efbafe` | 0 (Identical) |
| `candidate-bundle.bin` | 29,867,008 | `1859c778b5a3b72fa0e230af7c281c6f49d499534ffaa7c9e45af8fa9adcb456` | +15,872 bytes |

### 5.3 Subsystem Architecture & Component Inventory
- **Kernel Architecture**: Linux 6.12.0 ARMv7 multiplatform kernel (`vmlinux`, `zImage`, 28,615,168 bytes), targeting Apple S5L8942X (Cortex-A9 dual-core). Boot stamps verified in ELF binary: `irq_rearm`, `pre_spawn`, `umt_go`, `aic1q34`, `irq_try`.
- **Integrated Driver Stack**:
  - `CONFIG_CHARGER_APPLE_PMU=y` (`drivers/power/supply/apple-pmu-charger.c`): Dialog D1946 PMU USB input current limit control (100–2100 mA) with direct regmap 0x3d hardware readback, bounded sag retries (`sag_max_retries=3`), cooldown interval enforcement, and thermal derating veto ($45.0^\circ\text{C}$/$40.0^\circ\text{C}$).
  - `CONFIG_BATTERY_BQ27XXX=y` & `CONFIG_BATTERY_BQ27XXX_HDQ=y`: TI BQ27540 battery gas gauge via single-wire UART5 HDQ.
  - `CONFIG_MFD_APPLE_PMU=y`: Dialog D1946 core PMU via I2C bus 0 at `0x3c`.
  - `CONFIG_REGULATOR_APPLE_PMU_PWRSW=y`: PMU power switch regulator.
  - `CONFIG_TOUCHSCREEN_APPLE_Z2=y`: Touchscreen digitizer driver.
  - `CONFIG_DRM_APPLE_SGX=y` & `CONFIG_FB_SIMPLE=y`: PowerVR SGX543 GPU and simple framebuffer display.
  - `CONFIG_SND_SOC_APPLE_S5L_AUDIO=y`: Apple S5L SoC audio engine.
  - `CONFIG_USB_DWC2_PERIPHERAL=y`, `CONFIG_PHY_APPLE_S5L_USB=y`, `CONFIG_USB_CDC_COMPOSITE=y`: Peripheral gadget networking and ACM serial.
- **Embedded Initramfs Rootfs**:
  - Alpine Linux **3.24.1** ARMHF minirootfs embedded into kernel (`devices/a5/build/initramfs-root`, 37.6 MB uncompressed, 939 files).
  - Components: BusyBox 1.37.0, OpenRC init, musl 1.2.5, eudev, kmod, dropbear SSH server, wpa_supplicant, iw, fbkeyboard, bluez, dbus, alsa-utils, e2fsprogs, openssh-sftp-server.
  - Static ARM binaries: `/bin/peek`, `/sbin/p105-keys`, `/sbin/nandctl`, `/sbin/iosnand`, `/sbin/z2-boot`.
  - Pinned USB gadget networking: `10.55.0.2` on `usb0` (ACM console on `ttyGS0`).
- **RAM Rootfs Overlay Layer (`devices/a5/build/overlay`)**:
  - Packed as a `newc` CPIO archive at offset `0x1b55000` (1,207,296 bytes).
  - Hardware firmware: `lib/firmware/P105.mtprops` (Touchscreen), `lib/firmware/apple/sgx543.fw` (Display / GPU microkernel), `lib/firmware/brcm/brcmfmac4334.bin` (Wi-Fi), `lib/firmware/brcm/BCM4334B0.hcd` (Bluetooth).
  - Diagnostics & keys: `sbin/nandctl`, `usr/bin/nand-diag`, `etc/dropbear/dropbear_ed25519_host_key`, `root/.ssh/authorized_keys`, `etc/localtime`, `etc/build-date`.
  - Custom LegacyPad tools: `/usr/bin/legacypad-status` and `/usr/bin/legacypad-power` (pure sysfs telemetry).

---

## 6. Memory Limits & Heap Headroom Analysis

iBEC (iBoot-2261.30.37) operates under rigid memory constraints during decompression:
- **Load Buffer Limit (`LOAD_MAX`):** Maximum IMG3 container size is `0x3F00000` (`66,060,288 bytes`).
  - Candidate size: `33,605,468 bytes`. Margin: **30.95 MiB** (`32,454,820 bytes`).
- **Mach-O Segment Ceiling:** Mapped at `0x80000000` .. `0x81C79000`. The load buffer begins at `0x84000000`. Margin: **35.53 MiB**.
- **iBEC Heap Ceiling (`HEAP_ROOM`):** iBEC allocates a 48 MiB heap region starting at `0x8C000000`, of which at most 40 MiB (`41,943,040 bytes`) is available for `complzss` compressed payload expansion.
  - Candidate `complzss` body: `33,605,024 bytes` (32.05 MiB).
  - **Remaining Heap Headroom: 7.95 MiB (`8,338,016 bytes`)**.

---

## 7. Hardware Testing Policy & On-Device Recovery Plan

> [!IMPORTANT]
> **HOST-ONLY STATUS:**
> All packaging, unwrap, assemble, and rollback tests have been conducted **exclusively on host machines**.
> Physical iPad deployment has **NOT** been performed for this candidate build. Hardware trials remain strictly gated pending user authorization.

### 7.1 Safe On-Device Deployment & Rollback Protocol (When Authorized)
- **To deploy candidate image to iPad (safe update preserving original `.orig` backups):**
  ```bash
  OUT="$CASCADIA_ROOT/devices/a5/build/p105/pcless-candidate" ./devices/a5/tools/p105-pcless.sh install
  ```
- **To roll back to the previously active Cascadia version at any time:**
  ```bash
  ./devices/a5/tools/p105-pcless.sh rollback
  ```
- **To reinstall known-good baseline image cleanly:**
  ```bash
  OUT="$CASCADIA_ROOT/devices/a5/build/p105/pcless-known-good" ./devices/a5/tools/p105-pcless.sh install
  ```
- **To remove all Cascadia files and restore original stock iOS files:**
  ```bash
  ./devices/a5/tools/p105-pcless.sh remove
  ```

### 7.2 On-Device Boot Recovery & Access Plan
If Linux hangs or panics during the boot sequence before network or userspace services start:
1. **Host-Side SSH is Unreachable:** Do not expect network rollback tools to respond while the kernel is halted.
2. **Forced Cold Reboot to iOS:** Hold the physical **Power + Home** buttons together for 10 seconds until the screen goes blank and the Apple logo appears. Release buttons.
3. **Apple Boot Chain Resumption:** kloader operates purely in DRAM and leaves no persistent boot hook. A cold reboot resumes the native Apple SecureROM -> LLB -> iBoot chain, which boots iOS 8.4.1 normally.
4. **Accessing iOS Userspace:** Once iOS 8.4.1 boots, connect via Wi-Fi SSH, USB SSH (`iproxy 2222 22`), or MobileTerminal directly on screen to inspect logs (`/var/log/cascadia-linux.log`) or execute `rollback` / `remove`.
5. **DFU Fallback Recovery:** In the event that iOS fails to boot, enter DFU mode (hold Power+Home for 10s, release Power, keep holding Home for 10s) and restore with `iPad2,5_8.4.1_12H321_Restore.ipsw` via Legacy iOS Kit or iTunes.
