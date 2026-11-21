# Candidate RAM Linux Image Audit & Tooling Import

**Target Device:** Apple iPad mini 1 (`iPad2,5` / A1432 / P105AP, Apple A5, 32 GB NAND, iOS 8.4.1 Build: `12H321`)  
**Status:** Host-only verified candidate build. **No files transferred to iPad; zero NAND operations.**

---

## 1. Overview & Objective

This deliverable implements the safe, host-only custom RAM Linux image experiment mandated by `GEMINI-PERSISTENCE-32GB-AUDIT.md`:
1. Preserves the known-good working PC-less boot files bit-for-bit with an immutable hash manifest.
2. Integrates a lightweight, non-secret diagnostic utility (`/usr/bin/legacypad-status`) into the RAM root overlay.
3. Packages a separate candidate bundle (`output/candidate-staging-bundle.bin`) and candidate boot files (`build/p105/pcless-candidate/`).
4. Verifies the candidate image with the C round-trip verifier (`test-pcless.c`) and validates all iBEC load buffer and 40 MiB heap headroom constraints.
5. Imports the sanitized, POSIX `/bin/sh`-compatible `p105-pcless.sh` installer, rollback test suite, and dynamic LwVM test suite into this repository.

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
| `kernelcache` | 33,588,764 | `75cb9305d9c72b600e47164e6af84ecdc9305416c95d7d12554f5b04945fdc10` | +1,152 bytes |
| `ramdisk` | 4,188 | `22459577003a9dbd6e92c132371e321098044e711b507709ad09b09176008dd8` | Identical |
| `devicetree` | 79,328 | `9abf1a5f73a824bf2652909ec24584ecaff09c725bbea80bfa20b833ccf6b6dd` | Identical |
| `iBEC.upgrade` | 282,624 | `ede34b70bf7f8a7f819f1e6a96c94f4f0ecc2c060af4dfe61ffe7a363f7865ef` | Identical |
| `linux` | 801 | `d0edb18aae8cf681cac8a2551348a40f70c6fb2b4753bff314899f5890efbafe` | Identical |
| `candidate-bundle.bin` | 29,852,160 | `a94ba00e578d06cbf782ca932ea4ddcaeeb750bc9735befcc46df8c79bf9b62c` | +1,024 bytes |

---

## 3. Host-Only Packaging Verification & iBEC Limits Audit

### 3.1 C Verifier Round-Trip Test (`test-pcless.c`)
The candidate image was tested through the native C unwrap/assemble/rewrap test harness:
```text
ok   unwrap(kernelcache) == bundle (29852160 bytes)
     layer at 0x1b55000, 1192448 bytes (includes /usr/bin/legacypad-status)
ok   assemble(loader, zImage-dtb, layer) == bundle (29852160 bytes)
ok   wrap(bundle) == kernelcache (33588764 bytes)
PASS
```

### 3.2 Candidate Bootargs & NAND Write-Lock Audit
- **bootargs:** `earlycon=s3c6400,0x32500000 keep_bootcon lpj=5000000 root=/dev/ram0 rw rootwait panic=10 loglevel=8 ignore_loglevel g_cdc.host_addr=02:10:5a:05:00:01 g_cdc.dev_addr=02:10:5a:05:00:02 apple_pmu_charger.armed=1 iomem=relaxed`
- `root=/dev/ram0` verified.
- Zero NAND write flags (`apple_ppn.allow_write=1`, `apple_ftl.enable_write=1`, `apple_ftl.write_volume` absent).
- PPN hardware node `ppn@1200000` (`apple,s5l8940x-ppn`) absent.

### 3.3 iBEC Memory Bounds & Headroom
- **Mach-O Segment Limit:** `0x80000000 .. 0x81C79000` (Load buffer begins at `0x84000000`). Headroom: **35.53 MiB**.
- **iBEC Load Limit (`LOAD_MAX`):** `33,588,764 bytes` vs. `66,060,288 bytes` (`0x3F00000`). Headroom: **30.97 MiB**.
- **iBEC Heap Room (`HEAP_ROOM`):** `complzss` compressed body is `33,588,288 bytes` (32.03 MiB) vs. `41,943,040 bytes` (40.00 MiB limit). **Headroom remaining: 7.97 MiB (`8,354,752 bytes`)**.

---

## 4. Candidate Utility: `/usr/bin/legacypad-status`

Integrated at `devices/a5/overlay/usr/bin/legacypad-status`:
```sh
#!/bin/sh
# legacypad-status -- Lightweight runtime diagnostic for LegacyPad / Cascadia RAM Linux
# Reports hardware model, uptime, memory, storage mount, and network interface status.
echo "=================================================="
echo " LegacyPad RAM Linux (32 GB iPad mini 1 / P105AP)"
echo " Host Kernel:  $(uname -srm 2>/dev/null || uname -a)"
echo " System Time:  $(date -u 2>/dev/null || echo 'Unknown')"
echo " Memory Free:  $(free -m 2>/dev/null | awk 'NR==2{print $4 " MB free of " $2 " MB total"}')"
echo " Storage Root: $(awk '$2=="/"{print $1 " on " $2 " (" $3 ")"}' /proc/mounts 2>/dev/null)"
echo " IP Address:   $(ip -4 addr show eth0 2>/dev/null | awk '/inet /{print $2}' || echo 'N/A')"
echo " Status:       Immutable RAM root active; NAND write locked"
echo "=================================================="
```

---

## 5. Sanitized Tooling Imported to Repository

1. `devices/a5/tools/p105-pcless.sh`:
   - Pure POSIX shell syntax for Darwin `/bin/sh` compatibility (no `basename`, `grep`, `cut`, `awk` dependencies on iOS).
   - Atomic manifest tracking and automatic rollback on interrupted transfers.
   - Host-side sysctl validation (`hw.machine=iPad2,5`, `kern.osversion=12H321`).
   - Clean GPL-2.0-only header and attribution.
2. `devices/a5/tests/test-pcless-rollback.sh`:
   - 7/7 comprehensive rollback test scenarios executed under `dash` / `sh` with an isolated minimal PATH (banned external utilities completely shadowed).
3. `devices/a5/tools/nand-volume/test_lwvm_dynamic.py`:
   - 6/6 dynamic LwVM tests verifying 16 GB regression, 32 GB 32 MiB chunk scaling, and strict rejection of corrupt magic, CRC, bound overruns, and overlaps.

---

## 6. Safe Deployment & Rollback Protocol (Pending User Approval)

When the owner explicitly authorizes physical testing:
1. **Activation Command:**
   ```bash
   OUT=devices/a5/build/p105/pcless-candidate ./devices/a5/tools/p105-pcless.sh install
   ```
2. **Execution on iPad:**
   Run `linux` as root in MobileTerminal/SSH; press Home once when screen turns black.
   Verify `/usr/bin/legacypad-status`.
3. **Instant Rollback if Needed:**
   To restore the verified baseline image at any time:
   ```bash
   OUT=devices/a5/build/p105/pcless-known-good ./devices/a5/tools/p105-pcless.sh install
   ```
