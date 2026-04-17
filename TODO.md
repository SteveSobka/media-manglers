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

- [ ] Verify broader `Video Mangler.ps1` simulated OpenAI failure modes after PR #11
  Status: needs verification
  Current note: PR #11 validation explicitly covered `MM_TEST_OPENAI_MODE=quota` for `Video Mangler.ps1`, but the newly added unauthorized, permission-denied, timeout, network, rate-limit, and server-error branches were not all listed as validated for the video path during this merge pass.

## Recently Completed

- [x] Repo-only: merge validated OpenAI error-classification and quota-messaging work from PR #11
  Status: completed on 2026-04-16
  Current note: Merged PR #11 into `main` after removing accidental tracked `dist/Audio Mangler.exe` and `dist/Video Mangler.exe` changes so the approved merge content stayed limited to `Audio Mangler.ps1`, `Video Mangler.ps1`, and `README.md`.

## Parity Summary

Open GitHub issues represented here:

- None currently open.
