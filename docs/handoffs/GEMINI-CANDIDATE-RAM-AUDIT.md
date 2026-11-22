# Candidate RAM Linux Image Audit & Tooling Import

**Target Device:** Apple iPad mini 1 (`iPad2,5` / A1432 / P105AP, Apple A5, 32 GB NAND, iOS 8.4.1 Build: `12H321`)  
**Status:** Host-only verified candidate build. **No files transferred to iPad; physical hardware trials strictly gated.**

---

## 1. Overview & Operational Model

This deliverable implements the safe, host-only custom RAM Linux image experiment mandated by `GEMINI-PERSISTENCE-32GB-AUDIT.md`:
1. Preserves the known-good working PC-less boot files bit-for-bit with an immutable hash manifest.
2. Integrates an enhanced, non-secret diagnostic utility ([`/usr/bin/legacypad-status`](devices/a5/overlay/usr/bin/legacypad-status)) with dynamic network detection (`wlan0`/`usb0`/`eth0`) and runtime NAND write-lock validation into the RAM root overlay.
3. Packages a separate candidate bundle (`output/candidate-staging-bundle.bin`) and candidate boot files (`build/p105/pcless-candidate/`).
4. Verifies the candidate image with the native C round-trip verifier (`test-pcless.c`) and validates all iBEC load buffer and 40 MiB heap headroom constraints.
5. Imports the sanitized, POSIX `/bin/sh`-compatible [`p105-pcless.sh`](devices/a5/tools/p105-pcless.sh) installer, [`test-pcless-rollback.sh`](devices/a5/tests/test-pcless-rollback.sh) test suite (11/11 scenarios), [`lwvm.py`](devices/a5/tools/nand-volume/lwvm.py), and [`test_lwvm_dynamic.py`](devices/a5/tools/nand-volume/test_lwvm_dynamic.py) into this repository.

### Storage Operational Distinction: Host Install vs. Runtime RAM Linux
- **Host-Side Installation:** The preparatory installation command writes the 6 bootchain files (`/kernelcache`, `/ramdisk`, `/devicetree`, `/usr/local/cascadia/*`, `/usr/bin/linux`) directly to the iPad's iOS System partition (HFS+ volume on NAND).
- **Runtime Linux:** Once booted via `kloader` -> patched `iBEC.upgrade`, the entire Linux operating system resides in RAM (`root=/dev/ram0`). Runtime NAND write permissions are strictly locked and unconfigured.

---

## 2. Integrity Verification: Known-Good vs. Candidate Artifacts

### 2.1 Preserved Known-Good Baseline Manifest
All known-good boot artifacts remain 100% untouched and backed up in `devices/a5/build/p105/pcless-known-good/`:

| Artifact | Size (Bytes) | SHA-256 Checksum |
| :--- | ---: | :--- |
| `kernelcache` | 33,587,612 | `5ab87f2c6056fcd056d92ab5e24034803d4458d6a80ba59b178b21f7816c6967` |
| `ramdisk` | 4,188 | `22459577003a9dbd6e92c132371e321098044e711b507709ad09b09176008dd8` |
| `devicetree` | 79,328 | `9abf1a5f73a824bf2652909ec24584ecaff09c725bbea80bfa20b833ccf6b6dd` |
| `iBEC.upgrade` | 282,624 | `ede34b70bf7f8a7f819f1e6a96c94f4f0ecc2c060af4dfe61ffe7a363f7865ef` |
| `linux` | 801 | `d0edb18aae8cf681cac8a2551348a40f70c6fb2b4753bff314899f5890efbafe` |
| `staging-bundle.bin` | 29,851,136 | `90794c21d0f976047177d051b5175e28a722bc225894bb5700714700590a7a3f` |

### 2.2 Candidate Boot Artifacts Manifest
Candidate boot artifacts built independently in `devices/a5/build/p105/pcless-candidate/`:

| Artifact | Size (Bytes) | SHA-256 Checksum | Delta vs. Known-Good |
| :--- | ---: | :--- | ---: |
| `kernelcache` | 33,605,468 | `8e1cc0d7143142040c7dabbc7a6b4d156b76f3f99cb7640a676505f0f3dfcf87` | +17,856 bytes |
| `ramdisk` | 4,188 | `22459577003a9dbd6e92c132371e321098044e711b507709ad09b09176008dd8` | Identical |
| `devicetree` | 79,328 | `9abf1a5f73a824bf2652909ec24584ecaff09c725bbea80bfa20b833ccf6b6dd` | Identical |
| `iBEC.upgrade` | 282,624 | `ede34b70bf7f8a7f819f1e6a96c94f4f0ecc2c060af4dfe61ffe7a363f7865ef` | Identical |
| `linux` | 801 | `d0edb18aae8cf681cac8a2551348a40f70c6fb2b4753bff314899f5890efbafe` | Identical |
| `candidate-bundle.bin` | 29,867,008 | `1859c778b5a3b72fa0e230af7c281c6f49d499534ffaa7c9e45af8fa9adcb456` | +15,872 bytes |

---

## 3. Host-Only Packaging Verification & iBEC Limits Audit

### 3.1 C Verifier Round-Trip Test (`test-pcless.c`)
The candidate image was tested through the native C unwrap/assemble/rewrap test harness:
```text
ok   unwrap(kernelcache) == bundle (29867008 bytes)
     layer at 0x1b55000, 1207296 bytes (includes /usr/bin/legacypad-status and /usr/bin/legacypad-power)
ok   assemble(loader, zImage-dtb, layer) == bundle (29867008 bytes)
ok   wrap(bundle) == kernelcache (33605468 bytes)
PASS
```

### 3.2 Candidate Bootargs & NAND Write-Lock Audit
- **bootargs:** `earlycon=s3c6400,0x32500000 keep_bootcon lpj=5000000 root=/dev/ram0 rw rootwait panic=10 loglevel=8 ignore_loglevel g_cdc.host_addr=02:10:5a:05:00:01 g_cdc.dev_addr=02:10:5a:05:00:02 apple_pmu_charger.armed=1 iomem=relaxed`
- `root=/dev/ram0` verified.
- Zero NAND write flags (`apple_ppn.allow_write=1`, `apple_ftl.enable_write=1`, `apple_ftl.write_volume` absent).
- PPN hardware node `ppn@1200000` (`apple,s5l8940x-ppn`) absent.

### 3.3 iBEC Memory Bounds & Headroom
- **Mach-O Segment Limit:** `0x80000000 .. 0x81C79000` (Load buffer begins at `0x84000000`). Headroom: **35.53 MiB**.
- **iBEC Load Limit (`LOAD_MAX`):** `33,605,468 bytes` vs. `66,060,288 bytes` (`0x3F00000`). Headroom: **30.95 MiB**.
- **iBEC Heap Room (`HEAP_ROOM`):** `complzss` compressed body is `33,605,024 bytes` (32.05 MiB) vs. `41,943,040 bytes` (40.00 MiB limit). **Headroom remaining: 7.95 MiB (`8,338,016 bytes`)**.

---

## 4. Candidate Utility: `/usr/bin/legacypad-status`

Updated at `devices/a5/overlay/usr/bin/legacypad-status` with dynamic interface querying (`wlan0`, `usb0`, `eth0`) and runtime verification of `/proc/cmdline` and `/proc/mounts`:
- Dynamically parses `ip` and `ifconfig` for active IPv4 interfaces.
- Verifies that `/` is mounted on `/dev/ram0`.
- Verifies that zero NAND write flags exist in kernel arguments and zero writable NAND block devices are mounted.

---

## 5. Tooling & Test Suite Summary

1. [`devices/a5/tools/p105-pcless.sh`](devices/a5/tools/p105-pcless.sh):
   - Pure POSIX shell syntax for Darwin `/bin/sh` compatibility (no `basename`, `grep`, `cut`, `awk` dependencies on iOS).
   - Preserves `OUT` environment variable when deploying candidate or baseline images.
   - Transactional update mode: creates `$BK/previous/` backup before activating new files while keeping original `$BK/*.orig` untouched.
   - Dedicated `rollback` command to swap active files back to the previous version.
   - Host-side sysctl validation (`hw.machine=iPad2,5`, `kern.osversion=12H321`).
   - Clean GPL-2.0-only header and attribution.
2. [`devices/a5/tests/test-pcless-rollback.sh`](devices/a5/tests/test-pcless-rollback.sh):
   - 11/11 comprehensive test scenarios executed under `dash` / `sh` with an isolated minimal PATH (banned external utilities completely shadowed).
   - Verifies install, update, rollback, remove, mid-transfer abort, and `OUT` preservation.
3. [`devices/a5/tools/nand-volume/test_lwvm_dynamic.py`](devices/a5/tools/nand-volume/test_lwvm_dynamic.py):
   - 6/6 dynamic LwVM tests verifying 16 GB regression, 32 GB 32 MiB chunk scaling, and strict rejection of corrupt magic, CRC, bound overruns, and overlaps.
   - Self-contained in repository with [`lwvm.py`](devices/a5/tools/nand-volume/lwvm.py).

---

## 6. Safe Deployment & On-Device Boot Recovery Protocol (Pending User Approval)

When physical testing is explicitly authorized by the owner:
1. **Deployment Command (Safe Update):**
   ```bash
   OUT=devices/a5/build/p105/pcless-candidate ./devices/a5/tools/p105-pcless.sh install
   ```
2. **Execution on iPad:**
   Run `linux` as root in MobileTerminal or SSH; press Home once when screen turns black.
3. **Reverting to Previous Version:**
   ```bash
   ./devices/a5/tools/p105-pcless.sh rollback
   ```
4. **Reverting to Stock iOS (Complete Clean Removal):**
   ```bash
   ./devices/a5/tools/p105-pcless.sh remove
   ```

### On-Device Boot Hang / Crash Recovery Plan
If Linux halts during boot before userspace or networking is active:
1. **Hard Cold Reboot:** Hold **Power + Home** buttons simultaneously for 10 seconds until the Apple logo appears.
2. **Native iOS Boot:** Apple SecureROM and iBoot resume normal boot without kloader intervention, returning the device to iOS 8.4.1.
3. **iOS Access:** Reconnect via Wi-Fi SSH or MobileTerminal to review `/var/log/cascadia-linux.log` or execute rollback/remove.
4. **DFU Recovery (Worst Case):** Enter DFU mode (Power+Home 10s, release Power, hold Home 10s) and restore with `iPad2,5_8.4.1_12H321_Restore.ipsw`.
