# 32 GB NAND Readiness Engineering & Compatibility Audit — P105AP / iPad2,5

**Date:** 2026-11-22  
**Status:** Host-Only Engineering Audit, Upstream PR #52 Review & Read-Only PPN Diagnostic Candidate Record  
**Safety Mandate:** STRICTLY HOST-ONLY. No physical NAND writes, formatting, repartitioning, filesystem shrinking, flashing, or boot-image replacement. Passing simulated tests does NOT authorize flash writes.

---

## 1. Executive Summary & Objective

The primary objective of this engineering track is to systematically assess the requirements, risks, and blockers for **safe, persistent, fully offline Linux storage on the 32 GB iPad mini 1 (iPad2,5 / P105AP, iOS 8.4.1 12H321)** while strictly preserving the host iOS installation, jailbreak untether, and the known-good baseline RAM image (`pcless-known-good`, SHA-256: `5ab87f2c...`).

The current PC-less Alpine Linux system boots reliably in RAM (`root=/dev/ram0`), and the updated Dialog D1946 PMU charging driver has demonstrated positive battery charging current on device. However, physical persistent storage on 32 GB NAND remains an **unresolved research challenge**:
- Upstream Project Cascadia raw NAND repartitioning was originally designed and tested exclusively on a single 16 GB reference package (`040472P_HYNIX_B_`).
- **New Upstream Discovery (PR #52):** Independent upstream research revealed that even among 16 GB iPad mini 1 devices, Apple utilized multiple distinct NAND packages (e.g., `030800P` with 2088 blocks x 128 pages vs 1064 blocks x 256 pages). Physical row addressing bit layouts, VFL context block locations, signature words, and Swiss FTL layout sections are strictly package-dependent.
- **Physical 32 GB NAND Geometry is Completely UNKNOWN:** Our physical 32 GB device may possess different CE counts, CAUs, block counts, page depths, or row address bit shifts. Attempting to program or erase flash without knowing the physical NAND package is guaranteed to cause silent flash corruption and brick the device.
- An alternative hypothesis proposing file-backed ext4 loopback storage on iOS Data is **unverified and currently blocked**: iOS Data is hardware-encrypted (file-by-file per Apple Data Protection), and the PC-less RAM kernel operates with NAND writes disabled and no mounted Apple FTL/PPN block driver. Host-only POSIX file simulations do not validate on-device execution.

This engineering report:
1. Conducts an independent review of upstream Project Cascadia PR #52, analyzing its per-package geometry profile approach against our 32 GB changes.
2. Audits every remaining hardcoded 16 GB assumption across `nand-volume.sh`, `lwvm.py`, PPN, VFL, SFTL, header backup locations, and tools, while preserving our verified 32 GB LwVM dynamic capacity scaling.
3. Prepares an **isolated, host-only read-only PPN diagnostic kernel candidate** (`pcless-ppn-diag`, SHA-256: `c9fd3b87...`) using the working PC-less bootchain and proven PMU charging driver.
4. Enforces read-only behavior by construction: RAM rootfs (`root=/dev/ram0`), armed PMU charging (`apple_pmu_charger.armed=1`), disabled FTL auto-mount (`apple_ftl.auto_mount=0`), zero write flags, and fail-closed logging for unknown geometries.
5. Implements automated host-side regression tests verifying geometry profile detection, fail-closed read-only behavior on untested packages, and bootargs safety constraints.
6. Maintains the known-good baseline (`5ab87f2c...`) and candidate (`78dd1025...`) byte-for-byte unchanged.
7. Formulates a strict, evidence-based **GO/NO-GO** policy.

---

## 2. Independent Review of Upstream Cascadia PR #52

Upstream Project Cascadia PR #52 ([#52](https://github.com/rzxvx/Project-Cascadia/pull/52), related to [#51](https://github.com/rzxvx/Project-Cascadia/issues/51) and [#29](https://github.com/rzxvx/Project-Cascadia/issues/29)) introduces per-package geometry profiles and read-only probing.

### 2.1. Analysis of Commits in PR #52
- **`f4afc0e` (a5 ppn: read geometry from the package; untested packages probe read-only):**
  - Replaces hardcoded block and page limits in `check_params()` with dynamic extraction from the PPN parameter page: `blocks` (offset 0x18), `mlc_pages` (offset 0x20), `slc_pages` (offset 0x24), `cau_bits` (offset 0x14), `block_bits` (offset 0x1c), `page_bits` (offset 0x28).
  - Implements dynamic row address construction in `make_row()`:
    $$\text{cau\_shift} = \text{page\_bits} + \text{block\_bits}$$
    $$\text{row} = \text{page} \mid (\text{block} \ll \text{page\_bits}) \mid (\text{cau} \ll \text{cau\_shift}) \mid (\text{slc} \ll (\text{cau\_shift} + \text{cau\_bits}))$$
  - Reads PPN firmware string via feature 0x9080 (`FEAT_FIRMWARE`).
  - Sets `p->geo.supported = true` *only* for verified writable packages (`040472P_HYNIX_B_` and `030800P`). Any untested package sets `supported = false`.
  - If an untested package is loaded with `allow_write=1`, it refuses probe with `-ENODEV`. If loaded read-only (default), it logs a warning (`package firmware %16pE: unsupported, read-only`) and allows non-destructive probing to proceed.
  - In `apple_ppn_erase()` and `apple_ppn_program()`, operations are gated by `if (!allow_write || !p->geo.supported) return -EPERM;`.
- **`75003f9` (a5 sftl: per-package geometry profile; support 030800P (2088 x 128)):**
  - Introduces `struct sftl_geo` in `sftl.h` and selection function `sftl_geo_select(blocks, mlc_pages, slc_pages)` in `sftl_mount.c`.
  - Defines known profiles:
    1. `040472P_HYNIX_B_`: 1064 blocks x 256 MLC pages (SLC 128), 1055 SBs of 4096 LBAs, VFL blocks 1062/1063, sig word 16.
    2. `030800P`: 2088 blocks x 128 MLC pages (SLC 64), 2079 SBs of 2048 LBAs, VFL blocks 2086/2087, sig word 18.
  - Dynamically calculates context section lengths: SB array `sec_lbas(num_sb * 8)`, user sequences `sec_lbas(num_sb * 16)`, read counts `sec_lbas(num_sb * 4)`.
  - In `apple_ftl_main.c`: Calls `sftl_geo_select()`. If the package is unknown, FTL **strictly refuses to mount** (`pr_err("apple_ftl: no FTL profile...: not mounting")` and returns `-ENODEV`).
- **`42815c5` (a5 ppn: program_start takes the controller (row layout)):**
  - Updates `program_start()` to take `const struct apple_ppn *p` for dynamic row calculation during write phases.

### 2.2. Comparison Against Our 32 GB Downstream Changes
| Architectural Layer | Prior 32 GB Downstream Implementation | Upstream PR #52 Implementation | Engineering Synthesis & Resolution |
| :--- | :--- | :--- | :--- |
| **LwVM Logical Volumes (`lwvm.py`)** | Dynamic capacity scaling: 32 MiB chunk size, LBA 8191 backup, 953 chunks. Fail-closed validation. | Untouched (upstream retains 16 GB defaults in tools). | **PRESERVE DOWNSTREAM:** Our dynamic LwVM derivation is mathematically verified against openiBoot and required for 32 GB partition planning. |
| **PPN Row Addressing (`apple_ppn.c`)** | Hardcoded row shifts (8, 11, 4 bits) based on 1064x256 geometry. | Dynamic row construction from hardware parameters: `page_bits`, `block_bits`, `cau_bits`. | **ADOPT PR #52 ARCHITECTURE:** Hardcoding row shifts on unknown 32 GB dies is fatal. Row shifts must follow chip parameters. |
| **Writable Package Policy** | Assumed 32 GB could be made writable by doubling block count to 2128. | Untested packages probe **strictly read-only**; program/erase return `-EPERM`. | **ADOPT PR #52 SAFETY MANDATE:** Writable access is strictly prohibited until physical FTL and geometry dumps are analyzed offline. |
| **FTL Mounting (`apple_ftl_main.c`)** | Attempted to mount arbitrary geometries by expanding `SFTL_MAX_SB`. | `sftl_geo_select()` fails closed (`-ENODEV`) if geometry does not match a verified profile. | **ADOPT PR #52 FAIL-CLOSED MOUNT:** Prevents FTL driver from writing corrupted context blocks or superblock headers to unknown media. |

---

## 3. Comprehensive Audit of Hardcoded 16 GB Assumptions

An exhaustive audit of all storage and partition components across both repositories was conducted:

1. **`nand-volume.sh`:**
   - Line 39: `BOUND=15854493696` was a dormant hardcoded 16 GB constant. Note: Dynamic capacity bound is $31,708,962,816$ on 32 GB.
   - Header reading (`ios_read_header`): In Cascadia this hardcoded `skip=4095`. Verified that downstream already dynamically selects `skip=8191` for $\ge 32\text{ GB}$.
   - Header writing (`linux_write_header`): Downstream enforces a SHA-256 hash guard rejecting obsolete 16 GB `ppn_lwvmw.ko` binaries (`a4cb3c...`).
2. **`lwvm.py`:**
   - Downstream dynamic `media_geometry()` correctly computes:
     - 16 GB: `chunk_size = 16 MiB`, `nchunks = 953`, `bound = 15854493696`, `backup_lba = 4095`.
     - 32 GB: `chunk_size = 32 MiB`, `nchunks = 953`, `bound = 31708962816`, `backup_lba = 8191`.
   - Chunk map parsing enforces `M_HEADER` at index 0, partition chunk continuity, and `M_PAST` (0xF3FF) for chunks $953..1023$.
   - Fail-closed CRC and validator handling verified (17/17 tests passing).
3. **`apple_ppn.c`:**
   - Upstream base hardcoded `SFTL_BLOCKS = 1064`, `SFTL_MLC_PAGES = 256`, and row shifts $8, 11, 4$.
   - PR #52 eliminates hardcoded assumptions for parameter discovery, parsing `blocks`, `mlc_pages`, `slc_pages`, `cau_bits`, `block_bits`, and `page_bits` directly from the PPN Device Info page.
   - Probing is non-destructive and writable operations are denied by construction for unsupported hardware.
4. **`sftl.h` / `sftl_mount.c`:**
   - Upstream base hardcoded `SFTL_NUM_SB = 1055` and `SFTL_TOTAL_LBAS = 3906266`.
   - PR #52 isolates package geometry in `struct sftl_geo`. Untested packages return `-ENODEV`, preventing unverified FTL operations.
5. **Header Backup Locations:**
   - 16 GB: Primary LBA 0, Secondary LBA 4095 ($\frac{16\text{ MiB}}{4096} - 1$).
   - 32 GB: Primary LBA 0, Secondary LBA 8191 ($\frac{32\text{ MiB}}{4096} - 1$).
6. **Partition Calculations:**
   - System size: 68 chunks on 32 GB ($2,176\text{ MiB}$) vs 133 chunks on 16 GB ($2,128\text{ MiB}$).
   - Data size: 878 chunks on 32 GB ($28,096\text{ MiB}$) vs 813 chunks on 16 GB ($13,008\text{ MiB}$).

---

## 4. Architecture of the Isolated Read-Only PPN Diagnostic Candidate

To safely discover the physical properties of our 32 GB NAND without risking hardware damage or flash corruption, an **isolated read-only PPN diagnostic boot candidate** (`pcless-ppn-diag`) was prepared.

### 4.1. Design Invariants & Construction
1. **Isolated Disposable Build Artifacts:**  
   In compliance with safety mandates, working build artifacts (`zImage-dtb`, `candidate-zImage-dtb`, `pcless-known-good`, `pcless-candidate`) were NEVER modified in place. The diagnostic candidate is built in an independent configuration and stored in `devices/a5/build/p105/pcless-ppn-diag/`.
2. **Dedicated Read-Only Device Tree (`p105ap-nand-ro.dts`):**  
   - Includes base `p105ap.dts`.
   - Disables obsolete raw NAND node (`&nand { status = "disabled"; }`).
   - Declares `nand-fmi-clock` at 300 MHz.
   - Enables `ppn@1200000` (compatible `apple,s5l8940x-ppn`) with register maps for `fmi0`, `fmi1`, and `cdma`.
   - Sets safe diagnostic bootargs with `hold_probe=1`:
     ```text
     earlycon=s3c6400,0x32500000 keep_bootcon lpj=5000000 root=/dev/ram0 rw rootwait panic=10 loglevel=8 ignore_loglevel g_cdc.host_addr=02:10:5a:05:00:01 g_cdc.dev_addr=02:10:5a:05:00:02 apple_pmu_charger.armed=1 apple_ppn.hold_probe=1 apple_ftl.auto_mount=0
     ```
3. **Safety by Construction & Mathematical Proof of Disabled Writes:**
   - **Kernel Configuration:** Compiled with `CONFIG_APPLE_PPN=y`, `CONFIG_APPLE_SFTL=n`, `CONFIG_APPLE_SFTL_WRITE=n`, `CONFIG_CHARGER_APPLE_PMU=y`.
   - **Swiss FTL Completely Excluded:** Because `CONFIG_APPLE_SFTL=n`, `apple_ftl.o` is not compiled into the kernel. No FTL block devices (`/dev/ftl*`) can ever be registered.
   - **Binary Proof of Disabled Program/Erase Sequences:**
     Disassembly of the compiled binary (`vmlinux`) confirms `apple_ppn_erase` and `apple_ppn_program` are 8-byte immediate-return `-EPERM` stubs:
     ```assembly
     c0bbb174 <apple_ppn_erase>:
     c0bbb174:	e3e00000 	mvn	r0, #0
     c0bbb178:	e12fff1e 	bx	lr

     c0bbb17c <apple_ppn_program>:
     c0bbb17c:	e3e00000 	mvn	r0, #0
     c0bbb180:	e12fff1e 	bx	lr
     ```
   - **Transmission Code Stripped:** `tx_page()` is enclosed in `#ifndef SFTL_NO_WRITE` and completely absent from `vmlinux`.
   - **Held Probe on Boot (`apple_ppn.hold_probe=1`):** The driver returns `-ENXIO` at boot probe and does NOT touch NAND hardware until manual operator trigger.
   - **Rootfs is Purely RAM (`root=/dev/ram0`):** NAND root is not mounted.
   - **PMU Charging is Armed (`apple_pmu_charger.armed=1`):** The Dialog D1946 driver sets the input current limit to 1000 mA from early boot, actively charging the battery and preventing the critical cable drain incident.
   - **Zero Write Flags:** `apple_ppn.allow_write=1`, `apple_ftl.enable_write=1`, and `apple_ftl.write_volume` are strictly absent.
4. **Hardened DTB Replacement & Packaging:**
   - Validates FDT magic (`0xd00dfeed`), offset $>0$, and header `totalsize == file_size`.
   - Rejects corrupted or malformed input images immediately.
   - Uses unique isolated temporary directories (`mktemp -d /tmp/ppn-diag-build.XXXXXX`) with automatic trap cleanup.
   - Binary packaging and C round-trip verification:
     The candidate bundle (`ppn-diag-staging-bundle.bin`, 29,850,112 bytes) and Mach-O/IMG3 container (`kernelcache`, 33,586,460 bytes) passed 100% bit-for-bit unwrapping, overlay extraction, reassembly, and wrapping tests via `pcless.c`.

### 4.2. Diagnostic Candidate Artifact Hashes
| Artifact | Path | Size (Bytes) | SHA-256 Checksum |
| :--- | :--- | :--- | :--- |
| **Diagnostic Kernelcache** | `build/p105/pcless-ppn-diag/kernelcache` | 33,586,460 | `aca998f26a78b1300751d9abe96e975d15937fc5136310899985667c0680e80f` |
| **Diagnostic Bundle** | `output/ppn-diag-staging-bundle.bin` | 29,850,112 | `6ba19f4a081da26b489c629fb4dd966d5257dfd248b64e52565dd5451a44e5bc` |
| **Diagnostic zImage-DTB** | `output/ppn-diag-zImage-dtb` | 28,605,635 | `58bb9bb0fa848d1b191df5871f30a91176bc5e47854e75471c080064d1f2b4ff` |
| **Diagnostic DTB** | `output/p105ap-nand-ro.dtb` | 10,947 | `e439d528b939f60cb0a08e1e75ff89063febe7e96a4a6e0f3ddf817ea8bb56d4` |
| **iBEC Upgrade Loader** | `build/p105/pcless-ppn-diag/iBEC.upgrade` | 282,624 | `ede34b70bf7f8a7f819f1e6a96c94f4f0ecc2c060af4dfe61ffe7a363f7865ef` |
| **DeviceTree** | `build/p105/pcless-ppn-diag/devicetree` | 79,328 | `9abf1a5f73a824bf2652909ec24584ecaff09c725bbea80bfa20b833ccf6b6dd` |
| **Ramdisk** | `build/p105/pcless-ppn-diag/ramdisk` | 4,188 | `22459577003a9dbd6e92c132371e321098044e711b507709ad09b09176008dd8` |
| **Linux Launcher** | `build/p105/pcless-ppn-diag/linux` | 801 | `d0edb18aae8cf681cac8a2551348a40f70c6fb2b4753bff314899f5890efbafe` |

---

## 5. Physical Read-Only Identification Procedure (STRICTLY NOT EXECUTED)

> [!CAUTION]
> **STATUS: NOT EXECUTED / HOST-ONLY.**
> The commands below represent the documented procedure for hardware property discovery when physical device execution is authorized by the user. Do NOT execute without explicit authorization.

```bash
# ==============================================================================
# READ-ONLY PPN DIAGNOSTIC PROCEDURE (IPAD MINI 1 32 GB)
# ==============================================================================

# Step 1: Verify Host-Side Diagnostic Artifacts
cd /opt/LegacyPad-Linux
export CASCADIA_ROOT=/opt/Project-Cascadia
OUT=$CASCADIA_ROOT/devices/a5/build/p105/pcless-ppn-diag bash devices/a5/tools/p105-pcless.sh verify

# Step 2: Stage Diagnostic Files to Device (Over USB SSH)
# Uses atomic update mechanism, preserving stock iOS rollback manifests
OUT=$CASCADIA_ROOT/devices/a5/build/p105/pcless-ppn-diag bash devices/a5/tools/p105-pcless.sh update

# Step 3: Trigger PC-less Boot from Jailbroken iOS Shell
ssh root@localhost -p 2222 "linux"

# Step 4: Access Running Linux via USB Ethernet (CDC-ECM: 10.55.0.2)
ssh root@10.55.0.2

# Step 5: Controlled Manual PPN Hardware Probe via sysfs
# Diagnostic kernel booted with apple_ppn.hold_probe=1; hardware was NOT probed on boot.
# Verify driver is loaded and probe is held:
cat /sys/module/apple_ppn/parameters/hold_probe  # returns 1

# Release probe hold and manually bind the PPN platform controller:
echo 0 > /sys/module/apple_ppn/parameters/hold_probe
echo 31200000.ppn > /sys/bus/platform/drivers/apple-ppn/bind

# Step 6: Capture Physical NAND Properties from Kernel dmesg
dmesg | grep -Ei "ppn|apple_ppn|apple_ftl|geometry|firmware" > /tmp/ppn-hardware.log
cat /tmp/ppn-hardware.log

# Expected Telemetry Output on 32 GB Device:
#   apple_pmu_charger: armed=1, max_target=1000000 uA
#   apple_ppn 31200000.ppn: bus 0: id PPN 1.5.5
#   apple_ppn 31200000.ppn: bus 1: id PPN 1.5.5
#   apple_ppn 31200000.ppn: package geometry <BLOCKS> blocks x <PAGES> pages (SLC <SLC>)
#   apple_ppn 31200000.ppn: row bits page <PB> block <BB> cau <CB>: not the reference package
#   apple_ppn 31200000.ppn: package firmware <FW_STRING>: unsupported, read-only
#   (Note: Swiss FTL does not mount because CONFIG_APPLE_SFTL=n)

# Step 7: Post-Diagnosis Rollback to Working Candidate Image
# Reverts active files to candidate (78dd1025...) or known-good (5ab87f2c...)
OUT=$CASCADIA_ROOT/devices/a5/build/p105/pcless-ppn-diag bash devices/a5/tools/p105-pcless.sh rollback
```

---

## 6. Formal GO / NO-GO Determination

| Operational Path | Determination | Decision Rationale |
| :--- | :--- | :--- |
| **Raw NAND Repartitioning (`ppn_lwvmw.ko` / `apple_ftl.enable_write=1`)** | **`STRICT NO-GO`** | Physical 32 GB NAND geometry is completely unknown. Erasing or programming flash with incorrect row bit offsets or block counts destroys active iOS FTL structures and permanently bricks the device. |
| **File-backed Loopback on iOS Data** | **`BLOCKED / UNVERIFIED`** | Blocked by Apple Data Protection hardware encryption and lack of a verified read/write storage path in the RAM kernel. Host-side POSIX tests do not prove device execution. |
| **Read-Only PPN Diagnostic Boot (`pcless-ppn-diag`)** | **`CONDITIONAL GO`** | Ready for physical hardware execution when user authorizes it. Bootargs strictly enforce `root=/dev/ram0`, `apple_pmu_charger.armed=1`, `apple_ftl.auto_mount=0`, and zero write flags. Probing is read-only by construction. |
| **Current Working Baseline (`pcless-known-good`)** | **`GO (CURRENT BASELINE)`** | Fully verified, boots reliably, preserves iOS and NAND 100% untouched. SHA-256: `5ab87f2c...`. |

---

## 7. Automated Test & Verification Summary

All verification suites were executed against the updated codebase:

```
[1] test_lwvm_dynamic.py (21/21 PASSED in 0.038s):
    - test_16gb_geometry_regression                         [PASS]
    - test_16gb_synthetic_header_create_remove              [PASS]
    - test_32gb_header_properties                          [PASS]
    - test_32gb_plan_create_and_remove                     [PASS]
    - test_fail_closed_chunk_map_violations                [PASS]
    - test_fail_closed_corrupted_headers                   [PASS]
    - test_fail_closed_on_invalid_and_corrupt_crc           [PASS]
    - test_fail_closed_on_missing_dependency               [PASS]
    - test_fail_closed_on_validator_exception              [PASS]
    - test_interrupted_write_and_recovery_simulation       [PASS]
    - test_mocked_success_validator_cannot_bypass_corrupt_crc [PASS]
    - test_nand_diagnose_header_validation_and_audit        [PASS]
    - test_now_and_backup32_identical                      [PASS]
    - test_openiboot_dynamic_formula                       [PASS]
    - test_ppn_diagnostic_bootargs_safety_invariants       [PASS]
    - test_ppn_diagnostic_dmesg_parser                    [PASS]
    - test_pr52_package_profiles_and_untested_32gb_diagnostics [PASS]
    - test_review_fix_1_unbound_local_error_missing_firmware [PASS]
    - test_review_fix_2_reject_physical_logical_capacity_mismatch [PASS]
    - test_review_fix_3_block_on_invalid_ce_or_missing_backup [PASS]
    - test_review_fix_4_dmesg_parser_safety_and_ambiguity   [PASS]

[2] test-charge-gate.sh (10/10 PASSED):
    - All 10 fail-closed charging gate and telemetry scenarios passed.

[3] test-pmu-charger-faults.py (15/15 PASSED in 0.252s):
    - Sag retries, cooldown enforcement, and register 0x3d readback passed.

[4] test-power-diagnostics.sh (4/4 PASSED):
    - legacypad-power telemetry and sysfs monitoring passed.

[5] test-pcless-rollback.sh (11/11 PASSED):
    - POSIX sh atomic update, rollback, and cleanup scenarios passed.

[6] C Round-Trip Source Compilation & Verification (test-pcless):
    - Candidate Image (78dd1025...): unwrap, assemble, wrap identical [PASS]
    - Known-Good Image (5ab87f2c...): unwrap, assemble, wrap identical [PASS]
    - Read-Only PPN Diagnostic (aca998f2...): unwrap, assemble, wrap identical [PASS]
```

### Manifest & Baseline Integrity Check
```
Known-Good Image (Unchanged):
5ab87f2c6056fcd056d92ab5e24034803d4458d6a80ba59b178b21f7816c6967  pcless-known-good/kernelcache

Candidate PMU Charging Image (Unchanged):
78dd1025272fd711d99359a87f316a7bac53e3734d3a7e1ac62d3a983a6f6ee1  pcless-candidate/kernelcache

Read-Only PPN Diagnostic Candidate (Verified, Kernel Built with PPN=y, SFTL=n, hold_probe=1):
aca998f26a78b1300751d9abe96e975d15937fc5136310899985667c0680e80f  pcless-ppn-diag/kernelcache
```
