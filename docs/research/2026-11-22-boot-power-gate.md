# P105AP charging gate before further Linux development

**Date:** 2026-11-22  
**Hardware:** iPad mini 1 Wi-Fi (`iPad2,5` / P105AP), 32 GB-class NAND, iOS 8.4.1 (`12H321`)  
**State:** Host-side guard implementation and synthetic tests complete. **Not tested on the physical iPad.**

## Decision

The existing computer-free iOS-to-RAM Linux boot is a working recovery baseline, **not a completed durable Linux installation**. Preserve it. The charging candidate from draft PR #2 has not been booted on the owner's iPad. Do not proceed to hours of playback or any NAND volume write before a short, attended charging test passes.

Upstream [Cascadia issue #23](https://github.com/rzxvx/Project-Cascadia/issues/23) reports a physically tested input-current-limit driver on a **different** iPad mini 1, including +87 mA on a host and +615–626 mA on a 5 W wall supply. These measurements are evidence that the upstream approach can work, not a guarantee for this owner's charger, cable, modified driver, or 32 GB board.

## Implemented read-only guard

`devices/a5/overlay/usr/bin/legacypad-charge-gate` is a BusyBox-compatible script which only **reads** `/sys/class/power_supply/` and the charger module's `armed` flag. Reading the input limit through sysfs invokes the kernel driver's PMU-register **read**, but this script never writes PMU registers, installs packages, flashes storage, or powers off the device. Call it as `sh /usr/bin/legacypad-charge-gate` until executable file mode is verified in the rebuilt image.

- `--once` takes a snapshot; **a single passing reading is not charging acceptance**.
- `--gate` checks seven consecutive readings over six minutes, enough to span several configured 60-second retry windows. On **any** failure it stops with a nonzero exit status.
- The gate requires: battery present, charge ≥50%, temperature below 40 °C, power source online, charger armed, PMU input limit above 100 mA, and **net battery current at least +100 mA on every sample**.
- Missing, malformed or unreadable telemetry is an error, not a healthy reading.
- A driver-reported `input_current_limit` is a **limit**, not measured input current. Passing requires the independent battery gauge to report net charge too.

Host-side test: `sh devices/a5/tests/test-charge-gate.sh` — 10/10 controlled synthetic scenarios passed on 2026-11-22; this is not physical proof.

## Physical-test gate: requires separate owner approval

1. In **iOS**, charge to at least 70% with a dependable 10 W/12 W or better iPad-compatible wall supply, and make sure iOS still starts normally. Keep the approved known-good bundle/hashes and recovery instructions on the host.
2. Before upgrading boot files, use the existing `p105-pcless.sh check-ios` and **verify the intended candidate bundle and rollback target**. Only change the iOS System boot files with the user's explicit approval; never touch the NAND partition table or FTL directly.
3. Rebuild and verify the candidate image so it actually includes `legacypad-charge-gate`. Use the existing `p105-pcless.sh` **update/rollback** mechanism, then start Linux from iOS. All binary checks, sizes and actual on-device launch remain **NOT TESTED** for the new guard.
4. Immediately on the Linux console, with the power supply still connected, run `sh /usr/bin/legacypad-charge-gate --once`. If it fails, **stop testing and return to iOS**. A quick pass permits only the next step, not an extended workload.
5. With the operator watching, run `sh /usr/bin/legacypad-charge-gate --gate`. Stop on missing telemetry, current below +100 mA, PMU limit at or below 100 mA, overheating, cable disconnect, or any abnormal behavior. Report capacity and current over time without private device identifiers.
6. Only after a sustained pass, consider an additional short, attended audio load and repeat the guard. No unattended or overnight Linux use until repeated physical evidence supports it.

**Rollback:** Return to iOS (as already demonstrated), and use the existing previous-image rollback route if candidate charging fails. Do not delete the known-good files to save space. A reboot, clean iOS boot and resumed iOS charging are part of acceptance, not optional extras.

## Storage remains independent

This guard **does not** make `/dev/ram0` persistent. Runtime package installs and bookmarks still vanish on reboot. The owner's 32 GB LwVM headers appear to use **32 MiB chunks** and a backup copy at LBA 8191, but safe physical PPN/FTL writing remains unverified. The blocked NAND installation path is documented in [the 32 GB investigation](2026-11-21-p105-32gb-nand.md).

An interim reproducible image may preserve built-in *software defaults* across boots; it does not preserve changing *user data*. A home-network NFS root is useful for development but is not a standalone offline solution. USB mass storage and read-write use of iOS partitions are not proven safe alternatives on this unit. Do not describe any of them as a completed offline persistence mechanism.

**Next acceptance:** first charging on this unit, then reliable repeatable boot, then a separately reviewed persistence design, then media playback.
