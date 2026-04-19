# Hybrid Accuracy processing path for multilingual media

## Purpose

Add a new Hybrid Accuracy processing path that keeps source audio local, creates an authoritative source-language transcript first, and sends only text transcript content to OpenAI for higher-quality English translation and later validation.

## Current status

This plan is now historical implementation record, not an open execution gate.

- PR `#17` merged the Hybrid work into `main` on 2026-04-18.
- Issue `#16` is closed.
- Rig1 produced accepted longer-source Hybrid evidence for both wrappers plus a short French follow-on smoke.
- The current default Hybrid text model remains `gpt-4o-mini-2024-07-18`.

The first benchmark target is German audio or video processed as:

- German source audio
- German source-language transcript
- English translated transcript

## Historical PASS 1 scope

This document records the approved PASS 1 scaffold, not the full end-state implementation.

PASS 1 includes:

- `ProcessingMode Hybrid` scaffolding in both apps
- issue-linked repo tracking
- an initial German-to-English glossary asset
- a tracked Python helper skeleton for future Hybrid batching and validation
- lightweight non-OpenAI tests
- minimal operator-facing docs

PASS 1 does not complete:

- the full batched OpenAI text-translation pipeline
- retry and repair logic
- final validation scoring
- benchmark-quality evidence generation
- broader non-English target-language support

## v1 behavior target

Hybrid Accuracy is intended to mean:

- local audio download or extraction
- local Whisper source-language transcription using `task=transcribe`
- authoritative source transcript artifacts first
- OpenAI text-only translation to English
- no source-audio upload in this mode

Current v1 scope decisions:

- target language support: English only
- default lane id: `hybrid-medium-ai-translate`
- default privacy class: `audio local / text uploaded`
- existing `Local`, `AI Public`, and `AI Private` behavior must remain unchanged
- Hybrid is a new mode, not a redefinition of the current AI modes

## Branch and issue decision

- PASS 1 base branch: `origin/main`
- PASS 1 working branch: `wip/hybrid-accuracy-multilingual-2026-04-18`
- GitHub issue: `#16` `Add Hybrid Accuracy processing path for multilingual media`

This work must not branch from an active `rig1` branch, even when executed on Rig1.

## Rig1 execution note

This PASS 1 implementation was approved for a Rig1 execution pass. Any machine-local repo roots or evidence roots used during the pass are operator-local inputs only and are not canonical repo truth.

Tracked repo docs must not hard-code machine-local absolute paths as canonical project behavior.

## Follow-up work after merge

These are future follow-ups rather than blockers for the merged Hybrid v1 path:

- benchmark scoring/reporting integration
- broader target-language support
- broader glossary-profile support
- later GPU benchmarking
- optional compatibility validation on additional machines when useful

## Later benchmarking needs

After the feature is merged or otherwise stabilized enough for a benchmark pass:

- run later Rig1 GPU benchmarking as a separate follow-up
- compare Rig1 and DevBox behavior rather than treating one machine as canonical truth
- keep benchmark evidence repo-safe unless explicitly promoted into tracked docs
