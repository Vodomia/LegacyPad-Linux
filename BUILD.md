# Building & Verifying LegacyPad-Linux Candidate RAM Linux Images

**Target Device:** Apple iPad mini 1 (`iPad2,5` / A1432 / P105AP, Apple S5L8942X SoC, 32 GB NAND)  
**Host Firmware:** Apple iOS 8.4.1 (Build `12H321`)  
**License:** GPL-2.0-only  
**Attribution:** Derived from [Project Cascadia](https://github.com/rzxvx/Project-Cascadia) for [LegacyPad-Linux](https://github.com/Vodomia/LegacyPad-Linux).

---

## 1. Overview & Architectural Principles

This document provides complete instructions to reproduce and verify the candidate PC-less RAM Linux boot image from source on an x86_64 or aarch64 Linux host.

### Core Safety Invariants:
1. **100% RAM Rootfs (`/dev/ram0`):** The entire operating system, userspace, and overlay run exclusively in system memory.
2. **Zero NAND Writes:** NAND write support (`apple_ppn.allow_write=1`, `apple_ftl.enable_write=1`) is strictly disabled in boot arguments and kernel configurations. Physical NAND remains completely untouched.
3. **No External Cables or Network Dependencies:** Once booted via the iOS-side `kloader` -> patched `iBEC.upgrade` chain, Linux runs entirely standalone.
4. **iBEC Load & Heap Guardrails:** All generated artifacts are verified to stay well within iBEC's `0x3F00000` (66 MiB) image buffer limit and 40 MiB heap ceiling.
5. **Host-Only Verification:** All tests documented here have been executed strictly on the host PC. Physical device execution is gated and requires manual approval.

---

## 2. Prerequisites & Environment

### 2.1 Host Operating System & Packages
A standard Linux distribution (Debian, Ubuntu, Linux Mint, Fedora, Arch) with the following packages:
- `gcc` and `make` (Host build tools)
- `arm-linux-gnueabihf-gcc` and `arm-linux-gnueabihf-objcopy` (ARMv7 cross-toolchain)
- `python3` (>= 3.8)
- Standard core utilities: `bash`, `dash` (or `/bin/sh`), `stat`, `dd`, `cat`, `sha256sum`, `unzip`

```bash
# On Debian / Ubuntu / Linux Mint:
sudo apt-get update
sudo apt-get install -y build-essential gcc-arm-linux-gnueabihf python3
```

### 2.2 Proprietary Firmware Inputs (NOT in git repository)
In compliance with Apple copyright terms and open-source licensing, proprietary binaries are **never** committed to this repository. The user must provide the official Apple IPSW:
- **IPSW File:** `iPad2,5_8.4.1_12H321_Restore.ipsw` (MD5: `53f1d33cb8e11a141c22b102ce57eeea`)
- **Extracted iBEC:** `Firmware/dfu/iBEC.p105ap.RELEASE.dfu`
- **Extracted DeviceTree:** `Firmware/all_flash/all_flash.p105ap.production/DeviceTree.p105ap.img3`
- **kloader binary:** SHA-256 `bec212b4d99a1e3b9fa4add663fa884a2435045d1e47051415f4e26e197f8132`

---

## 3. Step-by-Step Reproduction Guide

### Step 1: Prepare the Custom Overlay
The RAM filesystem overlay accommodates system tools, configurations, and scripts unpacked by the kernel at boot over the base initramfs.

To integrate the `legacypad-status` diagnostic tool:
```bash
mkdir -p devices/a5/overlay/usr/bin
cp devices/a5/overlay/usr/bin/legacypad-status devices/a5/overlay/usr/bin/
chmod +x devices/a5/overlay/usr/bin/legacypad-status
```

### Step 2: Assemble the Candidate Boot Bundle
Run `assemble.py` to package the low-level loader, kernel, and overlay:
```bash
python3 devices/a5/scripts/assemble.py \
    devices/a5/output/linux-boot.bin \
    devices/a5/output/zImage-dtb \
    devices/a5/overlay \
    devices/a5/output/candidate-staging-bundle.bin
```
- **Loader:** Starts at `0x80000000`, padded to `0x8000` (32 KiB).
- **Kernel (`zImage-dtb`):** Located at `0x80008000`.
- **Overlay:** Packed as a `newc` CPIO archive starting at offset `0x1b55000`.

### Step 3: Patch iBEC for System Root Boot (`iBEC.upgrade`)
Apply PC-less patches to the decrypted iBEC using `patch-ibec-upgrade.py`:
```bash
python3 devices/a5/scripts/patch-ibec-upgrade.py \
    devices/a5/build/firmware/iBEC.patched \
    devices/a5/build/p105/pcless-candidate/iBEC.upgrade
```
- Bypasses NVRAM auto-boot checks (`auto-boot=true`).
- Sets default boot command to `upgrade`.
- Points the OTA mount target from partition `Update` to `System` (read-only HFS+).
- Removes NVRAM `saveenv()` calls to prevent any persistent wear or alteration of NVRAM.

### Step 4: Wrap Mach-O, Compress LZSS, and Pack IMG3 (`make-pcless.py`)
Package the candidate bundle into Apple img3 containers:
```bash
python3 devices/a5/scripts/make-pcless.py \
    --board p105 \
    --ipsw iPad2,5_8.4.1_12H321_Restore.ipsw \
    --bundle devices/a5/output/candidate-staging-bundle.bin \
    --devicetree devices/a5/build/firmware/DeviceTree.p105ap.img3 \
    --out devices/a5/build/p105/pcless-candidate
```
This generates:
- `kernelcache`: Mach-O segment at `0x80000000`, wrapped with Apple `complzss` and IMG3 `krnl` tag.
- `ramdisk`: Stub 4096-byte zero img3 (`rdsk`) required by iBEC upgrade flow.
- `devicetree`: Plaintext IMG3 (`dtre`).

---

## 4. Host-Side Verification Suite

All verification tests are strictly offline and run on the host system.

### 4.1 C Unpack & Round-Trip Verifier (`test-pcless.c`)
Compile and run the C verification tool:
```bash
gcc -Wall -Wextra -O2 -Idevices/a5/app -o /tmp/test-pcless \
    devices/a5/tests/test-pcless.c devices/a5/app/pcless.c

/tmp/test-pcless \
    devices/a5/build/p105/pcless-candidate/kernelcache \
    devices/a5/output/candidate-staging-bundle.bin \
    devices/a5/output/linux-boot.bin \
    devices/a5/output/zImage-dtb
```
Expected output:
```text
ok   unwrap(kernelcache) == bundle (29852160 bytes)
     layer at 0x1b55000, 1192448 bytes
ok   assemble(loader, zImage-dtb, layer) == bundle (29852160 bytes)
ok   wrap(bundle) == kernelcache (33588764 bytes)
PASS
```

### 4.2 Installer Atomic Rollback Test Harness (`test-pcless-rollback.sh`)
Execute the simulated POSIX `/bin/sh` installer test suite:
```bash
./devices/a5/tests/test-pcless-rollback.sh
```
Tests 7 scenarios:
1. Clean install of all 6 target files.
2. Manifest collision guard (refuses second install without remove).
3. Missing manifest guard (refuses deletion of unknown files).
4. Manifest-based clean remove and pre-existing canary restoration.
5. Atomic abort on manifest creation error.
6. Mid-flight transfer interruption with clean rollback (empty initial state).
7. Mid-flight transfer interruption with pre-existing file preservation.

### 4.3 Dynamic LwVM 16/32 GB Test Suite (`test_lwvm_dynamic.py`)
Run the dynamic chunk geometry and LwVM integrity tests:
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
| `kernelcache` | 33,588,764 | `75cb9305d9c72b600e47164e6af84ecdc9305416c95d7d12554f5b04945fdc10` | +1,152 bytes |
| `ramdisk` | 4,188 | `22459577003a9dbd6e92c132371e321098044e711b507709ad09b09176008dd8` | 0 (Identical) |
| `devicetree` | 79,328 | `9abf1a5f73a824bf2652909ec24584ecaff09c725bbea80bfa20b833ccf6b6dd` | 0 (Identical) |
| `iBEC.upgrade` | 282,624 | `ede34b70bf7f8a7f819f1e6a96c94f4f0ecc2c060af4dfe61ffe7a363f7865ef` | 0 (Identical) |
| `linux` | 801 | `d0edb18aae8cf681cac8a2551348a40f70c6fb2b4753bff314899f5890efbafe` | 0 (Identical) |
| `candidate-bundle.bin` | 29,852,160 | `a94ba00e578d06cbf782ca932ea4ddcaeeb750bc9735befcc46df8c79bf9b62c` | +1,024 bytes |

---

## 6. Memory Limits & Heap Headroom Analysis

iBEC (iBoot-2261.30.37) operates under rigid memory constraints during decompression:
- **Load Buffer Limit (`LOAD_MAX`):** Maximum IMG3 container size is `0x3F00000` (`66,060,288 bytes`).
  - Candidate size: `33,588,764 bytes`. Margin: **30.97 MiB**.
- **Mach-O Segment Ceiling:** Mapped at `0x80000000` .. `0x81C79000`. The load buffer begins at `0x84000000`. Margin: **35.53 MiB**.
- **iBEC Heap Ceiling (`HEAP_ROOM`):** iBEC allocates a 48 MiB heap region starting at `0x8C000000`, of which at most 40 MiB (`41,943,040 bytes`) is available for `complzss` compressed payload expansion.
  - Candidate `complzss` body: `33,588,288 bytes` (32.03 MiB).
  - **Remaining Heap Headroom: 7.97 MiB (`8,354,752 bytes`)**.

> [!WARNING]
> Do NOT pack large monolithic binaries or packages into the RAM overlay that exceed the remaining 7.97 MiB headroom. Exceeding this boundary causes silent heap corruption in iBEC and boot failure.

---

## 7. Hardware Testing Status & Policy

> [!IMPORTANT]
> **HOST-ONLY STATUS:**
> All packaging, unwrap, assemble, and rollback tests have been conducted **exclusively on host machines**.
> Physical iPad deployment has **NOT** been performed for this candidate build.
> In accordance with safety policies, hardware trials remain strictly gated pending user authorization.

### Deployment & Recovery Commands (When Authorized)
- To deploy candidate image to iPad:
  ```bash
  OUT=devices/a5/build/p105/pcless-candidate ./devices/a5/tools/p105-pcless.sh install
  ```
- To revert to known-good baseline image immediately:
  ```bash
  OUT=devices/a5/build/p105/pcless-known-good ./devices/a5/tools/p105-pcless.sh install
  ```
