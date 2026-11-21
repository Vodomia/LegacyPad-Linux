# Project charter — LegacyPad Linux

## Problem

Many old tablets have good screens, batteries, and speakers but obsolete browsers and application ecosystems. This project explores whether a Linux-based, low-overhead, **offline-first learning appliance** can give them a useful second life.

## First device and user scenario

- Device: iPad mini 1 (A1432 / iPad2,5 / p105ap), 32 GB, roughly 512 MB physical RAM.
- Primary media: educational videos, lectures, long conversations, courses, and audio lessons.
- User may take the tablet outside the home, without a laptop, server, or Wi-Fi.
- Secondary priorities: resume playback, playlists/subjects, adjustable speed, subtitles/transcripts, bookmarks and notes, simple file synchronization, and battery efficiency.

## Product values

1. **Offline-capable:** downloaded lessons and progress survive shutdown, without requiring home NFS.
2. **Accessible:** touch targets, legible text, minimal navigation, no desktop expertise required.
3. **Lean:** no Chromium-class browsing requirement; a native player and compact shell UI are preferred.
4. **Trustworthy:** content provenance, integrity checks, privacy, no risky flash operations by default.
5. **Maintainable:** public English documentation; clear upstream boundaries and reproducible tests.

## MVP acceptance criteria

- A local, legally obtained sample lecture plays with usable audio and video on the physical tablet.
- Memory, CPU, battery impact, and frame drops are measured across at least a 20-minute sample.
- A simple touch workflow can choose a lesson, pause, seek, and return to the library.
- A verified and **safe persistent media path** survives two cold boots.
- The device can start without a laptop and play a previously synced lesson with Wi-Fi disabled.
- A new maintainer can reproduce the build without private credentials or undistributable Apple firmware in the repository.

The final three criteria are **not yet met**.

## Non-goals for the first milestone

- Making modern YouTube/streaming websites run directly in a full browser.
- Replacing iOS completely.
- High-definition playback claims without a measured decoder.
- Building a commercial service, paid subscriptions, or multi-device support before the single-device MVP works.
- Flashing/repartitioning the current unverified 32 GB NAND.

## Product boundaries

`Project Cascadia` supplies hardware and Linux bring-up. `LegacyPad Linux` develops the media workflow, light UI, offline library model, deployment tests, and end-user documentation. Changes needed upstream should be proposed as isolated, credited patches instead of silently forking a large, changing hardware tree.

Content acquisition must respect copyright, platform terms and the user's rights to obtain each recording.
