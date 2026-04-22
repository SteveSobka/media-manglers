# CODEX_INTERACTION_PROTOCOL.md

## Purpose

This document defines the durable Codex handoff workflow for this project.

## Handoff Modes

- Every Codex handoff should be labeled `PLAN MODE` or `EXECUTE MODE`.
- Default to `PLAN MODE` first if the handoff does not specify a mode.
- Do not move to `EXECUTE MODE` until the current plan is explicitly approved.

## Default Working Assumptions

- Unless the user says otherwise, assume `VS Code` as the editor surface.
- Unless the user says otherwise, assume `GPT-5.4` with high or very high reasoning.
- Keep repo work PowerShell-friendly and beginner-friendly.

## Plan Handling

- Approved plans should be saved as dated markdown files under `docs/plans/` unless a higher-precedence repo location is explicitly chosen later.
- Approved plans should also be shared with the project sources or handoff materials used by the team.
- If a plan is superseded, say so explicitly instead of silently rewriting history.

## Execute Handling

- In `EXECUTE MODE`, name the approved plan file at the start of the pass.
- Stay inside the approved scope unless the user explicitly broadens it.
- Update `TODO.md` as work starts and again when the pass ends.
- Report blockers, risks, and unverified items plainly instead of guessing.

## Evidence Handling

- Follow `governance/LATEST_EVIDENCE_POINTER.md` and `governance/CURRENT_PROJECT_TRUTH.md` first.
- Use local evidence as reference input unless it is explicitly promoted into tracked repo docs.
- Do not place machine-local absolute paths into tracked repo docs unless explicitly approved.
