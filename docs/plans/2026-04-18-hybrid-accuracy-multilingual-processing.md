# Hybrid Accuracy processing path for multilingual media

## Purpose

Add a new Hybrid Accuracy processing path that keeps source audio local, creates an authoritative source-language transcript first, and sends only text transcript content to OpenAI for higher-quality English translation and later validation.

The first benchmark target is German audio or video processed as:

- German source audio
- German source-language transcript
- English translated transcript

## PASS 1 scope

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

## Follow-up validation needs

These remain open after PASS 1:

- DevBox CPU validation for the new Hybrid mode
- live OpenAI text-translation validation on a short safe fixture
- full batched Hybrid translation implementation
- validation report generation integrated into package output
- benchmark evidence proving the German Hybrid lane improves on the current AI benchmark caveats

## Later benchmarking needs

After the feature is merged or otherwise stabilized enough for a benchmark pass:

- run later Rig1 GPU benchmarking as a separate follow-up
- compare Rig1 and DevBox behavior rather than treating one machine as canonical truth
- keep benchmark evidence repo-safe unless explicitly promoted into tracked docs
