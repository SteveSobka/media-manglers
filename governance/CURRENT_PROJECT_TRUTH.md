# CURRENT_PROJECT_TRUTH.md

## Purpose
This document defines the canonical truth for the project.

If other repo content disagrees, this document wins.

---

## ⚠️ Initialization Required
If any section below contains placeholders like `[REQUIRED]`, `[TBD]`, or lacks meaningful content:

- STOP.
- Do not proceed with implementation.
- Do not write code, modify files, or continue execution until resolved.
- Ask the user to provide the missing information.
- Offer a concise prompt to gather the required details, preferably in one short list.
- If this file is still in template state, repo initialization takes priority over feature work.

---

## Product Identity
Media Manglers started as a practical way to break video and audio into pieces that AI can review more accurately.

I originally built it for sim racing. High-frame-rate footage moves fast, and generic AI video review kept missing the details I actually cared about. When I wanted to understand a braking zone, a side-by-side corner entry, or the difference between one lap and another, handing AI one giant video file usually produced broad summaries instead of useful review.

I am not a traditional programmer, and that is part of the story here. I built this collaboratively with AI, using a lot of iteration, testing, re-explaining, and course-correcting until the outputs matched the workflow I needed. What mattered was solving a real problem (collaborating with AI to review video footage).

Instead of treating media like one giant blob, Media Manglers turns it into a review package: proxy media, extracted frames, audio, transcripts, optional translations, comments exports, and optional upload-ready bundles for AI review.

It started as a personal tool, but the workflow turned out to be useful for anyone who needs to inspect, summarize, translate, and hand off media without juggling five different utilities.

That is what this project does: it turns messy, fast-moving media into something you can review on purpose.

---



## Current State
- Project stage: alpha
- Known limitations: Requires Powershell

---

## Evidence and Truth Rules
- Repo governance docs define current truth.
- Current repo behavior and validation define implementation reality.
- External or historical references are guidance only unless explicitly adopted.
- Local-only inputs such as `AREA51/` and machine-local temp/evidence folders are reference-only unless explicitly promoted into tracked repo material.
- When evidence and assumptions conflict, evidence wins.

---

## Work Tracking Rule
- GitHub Issues are the canonical tracker for active work.
- `TODO.md` is the repo-visible board and must reflect current work.
- Work must not exist in multiple disconnected tracking systems.

---

## Stability Rule
- Do not redefine previously validated behavior without explicit approval.
- Changes must be incremental and testable.
- If something is uncertain, it must be treated as unproven, not assumed.

---

## Scope Guard
- Do not expand the project beyond Product Identity without explicit approval.
- If new capabilities or workflows are introduced, they must be added here before implementation.

---

## Document precedence
Use repo truth in this order:
1. `governance/CURRENT_PROJECT_TRUTH.md`
2. `AGENTS.md`
3. `TODO.md`
4. relevant current validation/evidence for the scoped task

If documents disagree, call out the mismatch and follow the highest-precedence current source.
