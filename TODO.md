# TODO

This is the repo-visible issue-first board.

Rules:

- GitHub Issues are the canonical active work tracker.
- Every open GitHub issue must have a visible home here.
- If an open issue appears stale, partially fixed, or contradicted by the current workstream, keep it open here as `needs verification` until testing, validation, or operator review confirms the real status.
- Use `repo-only` only for active work that is intentionally not tracked by an open GitHub issue.
- Do not create fake backlog items just to fill the template.

## Active Workstreams

No open GitHub issues are currently active in this repo.

## Repo-Only Active Work

- [ ] Consider partial-success-aware validation for `AREA51\Validate-VideoToCodexPackage.ps1`
  Status: repo-only follow-up
  Current note: The current validator assumes translated transcript files exist whenever `translations\<lang>\` exists, so expected partial-success OpenAI failure packages report missing translation artifacts instead of validating the operator-facing partial-package outputs.

## Recently Completed

- [x] Repo-only: verify `Video Mangler.ps1` simulated OpenAI failure-mode parity after PR #11
  Status: completed on 2026-04-16
  Current note: Verified `MM_TEST_OPENAI_MODE=unauthorized`, `permission_denied`, `timeout`, `network`, `rate_limit`, and `server_error` against `Video Mangler.ps1`. For every case, `script_run.log`, `README_FOR_CODEX.txt`, `PROCESSING_SUMMARY.csv`, and the final console summary reported the expected category-specific provider text, operator note, next step, and partial-success status. No operator-facing audio/video mismatch was observed in this pass.

- [x] Repo-only: merge validated OpenAI error-classification and quota-messaging work from PR #11
  Status: completed on 2026-04-16
  Current note: Merged PR #11 into `main` after removing accidental tracked `dist/Audio Mangler.exe` and `dist/Video Mangler.exe` changes so the approved merge content stayed limited to `Audio Mangler.ps1`, `Video Mangler.ps1`, and `README.md`.

## Parity Summary

Open GitHub issues represented here:

- None currently open.
