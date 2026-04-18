# AGENTS.md

## Product identity
For current repo-canonical truth and evidence precedence, read:
- `governance/CURRENT_PROJECT_TRUTH.md`

## Read first order
1. newest evidence pointer for the current pass
2. `governance/CURRENT_PROJECT_TRUTH.md`
3. `AGENTS.md`
4. `TODO.md`
5. `README.md` when repo orientation matters
6. `governance/FOREGROUND_VISUAL_WORK_PROTOCOL.md` when the pass includes visible desktop or UI work
7. `.gitignore` when local-only material, artifacts, or output handling matters

## Non-negotiable product decisions
- Do not contradict `governance/CURRENT_PROJECT_TRUTH.md`
- Do not introduce new architecture or workflows without explicit approval
- If `governance/CURRENT_PROJECT_TRUTH.md` is still in template state, treat truth initialization as the first task

## Current operator contract
- Optimize for operator usability, clarity, and safe execution
- Prefer simple, explainable behavior over clever or complex design

## Current release-candidate rule
- Do not redefine previously validated behavior without explicit approval
- New work should build incrementally and be testable

## Work tracking rules
- TODO.md is the repo-visible running work board and must be kept current.
- GitHub Issues are the canonical tracker for work that merits formal tracking.
- Every meaningful work item must appear in TODO.md, even if no GitHub Issue exists yet.
- If a new task, bug, risk, or follow-up is discovered during a pass, add it to TODO.md.
- If the work is substantial, cross-cutting, blocked, or likely to span multiple passes, create or propose a GitHub Issue.
- When starting work, review TODO.md first and reconcile it with the current branch, open work, and recent findings.
- When finishing work, update TODO.md to reflect what was completed, what remains open, what is blocked, and what needs verification.
- Do not mark work closed in TODO.md unless the current repo state and available evidence support closure.
- If GitHub Issue access is unavailable in the current surface, still update TODO.md and explicitly list any issues that should be created, updated, commented on, or closed.

## Local-only workspace rules
- `AREA51/` at repo root is the local-only working folder.
- Treat anything in `AREA51/` as non-canonical local input unless explicitly promoted into tracked repo files.
- Never stage, commit, mirror, or summarize sensitive `AREA51/` content into tracked code, docs, issues, PR text, or releases unless explicitly approved.
- If a pass depends on `AREA51/`, say so plainly and describe it at a high level without leaking secrets.
- Do not hard-code machine-local paths into tracked repo docs unless explicitly approved.

## Local evidence and temp workspace assumptions
- When the current machine provides a dedicated evidence workspace, prefer `D:\DATA\EVIDENCE` as the primary local evidence root for this project.
- Depending on the machine, scratch or temp workspace may also live under `C:\DATA\TEMP` or `D:\DATA\TEMP`.
- These locations are local-only reference inputs and working areas, not canonical repo truth, and they should not be mirrored into tracked repo docs unless explicitly approved.

## Visual / foreground work rules
- For visible desktop or UI work, follow `governance/FOREGROUND_VISUAL_WORK_PROTOCOL.md`.
- Do not assume local helper scripts or machine-specific GUI docs exist unless they are tracked in the repo.
- Keep machine-specific helper paths and low-level desktop automation detail out of tracked repo docs unless explicitly approved.

## Working rules for Codex
Before major code changes:
1. review the newest evidence pack first
2. compare with legacy references when behavior is disputed
3. update/create issues first when the pass is issue-scoped
4. state assumptions
5. implement only the scoped task
6. report what changed, what remains blocked, and how to test it

Do not hide unrelated defects inside another issue.
Do not broaden scope without explicit approval.
If a feature is not trustworthy yet, say so plainly.

## Additional settled rules
- repo governance docs are the canonical current-truth source
- external/local evidence is reference-only unless explicitly promoted
- Prefer clarity over completeness
- Do not guess when evidence is missing — call it out
- If TODO.md and other repo context disagree, reconcile them explicitly and call out the mismatch.
