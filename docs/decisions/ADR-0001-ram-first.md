# ADR-0001: RAM-first experiments, no NAND writes

- **Status:** Accepted for initial development
- **Date:** 2026-11-21
- **Context:** Real iPad mini 1, `iPad2,5 / p105ap`, iOS 8.4.1, 32 GB NAND.

## Context

A PC-less iBEC boot and Alpine RAM root have already worked on this device. Earlier attempts to adapt the Linux NAND volume failed with incompatible or interrupted LwVM headers. Offline diagnostics did not prove the physical 32 GB NAND controller and flash translation layer compatible with the available writer.

Project Cascadia has upstream NAND support, but the maintainer describes the global FTL as capable of affecting iOS's entire flash map on error. Its success on other hardware is not proof of safety for this 32 GB package.

## Decision

1. Do media, UI, network and packaging experiments in RAM; preserve a known-good boot image.
2. Permit read-only examination of hardware and the iOS System partition.
3. Prohibit repartitioning, NAND/FTL write enablement, USB-host power experiments and iOS Data mutation in routine tasks.
4. Treat any future NAND approach as a separate proposal with hardware identification, independent validator, tested backups/recovery, owner consent and a stop condition.
5. Clearly label all volatile demonstrations as **not yet portable offline storage**.

## Consequences

- Experiments are more recoverable and cheaper to iterate.
- Every reboot forgets the current root's packages and settings.
- The long-term offline-learning goal remains blocked by persistent media storage.
- A safe storage solution may eventually require extra hardware or a later, independently verified flash driver.

## Sources

- [Project Cascadia A5 NAND explanation at pinned revision](https://github.com/rzxvx/Project-Cascadia/blob/ad28ba40ba6f2a1d244ab51b637ceb31155fa126/devices/a5/README.md#how-the-nand-is-shared-with-ios)
- [PC-less boot research at pinned revision](https://github.com/rzxvx/Project-Cascadia/blob/ad28ba40ba6f2a1d244ab51b637ceb31155fa126/devices/a5/docs/research/p105-pcless-boot.md)
