# Contributor and agent operating rules

These rules apply to human and AI contributors working in this repository.

1. **English only in repository content:** source comments, documentation, issues, PRs, test names, commit messages, and public release notes. User conversations may use other languages.
2. **Evidence first:** separate what was observed on the physical 32 GB iPad, what upstream reports on other units, and unverified hypotheses. Record hardware model, iOS version, Alpine version, date, test method, and sanitized result.
3. **Do not touch NAND by default.** No repartitioning, direct flash writes, FTL writes, restoration, or modifications of iOS Data. A new proposal requires separate hardware-specific compatibility evidence, a recovery plan, and explicit owner authorization.
4. **Keep experiments reversible.** Prefer read-only diagnostics and RAM-root tests, with a clear effect statement. Describe changes to the iPad separately from changes to a development machine.
5. **Secrets stay out of Git.** Never commit passwords, Wi-Fi passphrases, private keys, access tokens, private IP addresses, unique device identifiers, full serial numbers, Apple-derived IPSWs, copyrighted lesson media, or raw user logs that may contain those fields.
6. **Respect upstream and licenses.** Cite the exact Project Cascadia commit used, do not present upstream features as original work, and do not vendor firmware or unreviewed third-party binaries. Audit licensing before copying code.
7. **No guesswork presented as compatibility.** GPU display support is not evidence of a hardware video decoder. An Alpine package listing is not proof that it starts or plays smoothly on this device.
8. **Measure before optimizing.** Record command, media file's codec/resolution/frame rate, audio output, memory delta, CPU usage, dropped frames, errors, and whether SSH survives.
9. **Use focused branches and pull requests.** Keep changes small, explain risks and tests, do not rewrite unrelated files, and do not force-push shared history.
10. **Avoid agent budget waste.** Read this file, the relevant ADR and status document first. Search only task-relevant paths, reuse existing evidence, and stop when blocked rather than repeatedly retrying.
11. **Do not claim completion from simulations alone.** Local format/rollback tests cannot validate iBEC boot, GPU playback, or NAND behavior on real hardware. State the last physical-device result honestly.
12. **Reproducibility:** pin upstream commits and package versions when tests become stable. Every milestone must have an acceptance test and a rollback story.

## Safe workflow

- Read `README.md`, `docs/HARDWARE_BASELINE.md`, and the relevant `docs/decisions/` entry.
- Define one bounded experiment, expected output, safety classification, and stop conditions.
- Gather and sanitize evidence. Do not install or flash without explicit scope.
- Implement on a feature branch, test locally, document physical-device evidence separately, and open a reviewable PR.
- Update `docs/ROADMAP.md` only after the acceptance criteria actually pass.

## Current non-negotiable guardrail

The 32 GB NAND/FTL installation route is **BLOCKED** on this physical unit until hardware compatibility is independently verified. The already working iOS-to-RAM Linux boot is the supported experimental path.
