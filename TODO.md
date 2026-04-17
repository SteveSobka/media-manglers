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

- [ ] Review remaining Audio Mangler OpenAI parity after this pass
  Status: repo-only follow-up
  Current note: This pass aligned key-selection and comments-prompt behavior across both apps, but the verified live Windows PowerShell 5.1 UTF-8/non-ASCII fix and the `MM_OPENAI_DIAGNOSTICS` troubleshooting path were only validated in `Video Mangler.ps1`. `Audio Mangler.ps1` already passed a live OpenAI run in this workstream, but a narrower parity review is still open before claiming full troubleshooting parity.

- [ ] Add durable regression coverage for Windows PowerShell 5.1 non-ASCII OpenAI transcript content
  Status: repo-only follow-up
  Current note: The `Video Mangler.ps1` bug is fixed and live-verified, but the repo still lacks permanent scripted coverage that proves UTF-8 transcript reads and UTF-8 request-byte sending stay correct for non-ASCII segments on Windows PowerShell 5.1.

## Recently Completed

- [x] Repo-only: document OpenAI integration, Private/Public guidance, and safe key selection defaults
  Status: completed on 2026-04-16
  Current note: `README.md`, `docs/guides/VIDEO_MANGLER.txt`, and `docs/guides/AUDIO_MANGLER.txt` now explain that OpenAI API use is optional, separate from ChatGPT subscriptions, and depends on API billing/credits. Both scripts now default to Private via `OPENAI_API_KEY_PRIVATE`, require an explicit `-OpenAiProject Public` choice for `OPENAI_API_KEY_PUBLIC`, and keep `OPENAI_API_KEY` as a legacy Private fallback for older setups.

- [x] Repo-only: change the interactive YouTube comments prompt to default Yes on Enter
  Status: completed on 2026-04-16
  Current note: `Video Mangler.ps1` and `Audio Mangler.ps1` now keep the prompt text `If comments are available for a YouTube source, save them in the package too? (y/N):`, but pressing Enter accepts comments by default and explicit `No` still skips them. The README and operator guides were updated to match.

- [x] Repo-only: fix live OpenAI video translation HTTP 400 in `Video Mangler.ps1`
  Status: completed on 2026-04-16
  Current note: Verified the live failure root cause in Windows PowerShell 5.1. `Get-TranscriptSegments` read UTF-8 transcript JSON without `-Encoding UTF8`, so the scripted segment-6 request sent mojibake text (`Das heiÃŸt ... wÃ¤hrend`) instead of the real German segment (`Das heißt ... während`). Separately, `Invoke-RestMethod` sending the chat-completions body as a plain string still reproduced `HTTP 400` for the correct non-ASCII segment, while an explicit UTF-8 byte body succeeded. `Video Mangler.ps1` now reads transcript JSON as UTF-8 and sends OpenAI chat-completions bodies as UTF-8 bytes. The pre-fix scripted failure was captured at `test-output\codex-openai-video-diagnostics-20260416-195458`, and the post-fix live rerun at `test-output\codex-openai-video-fixed-20260416-195833` completed all 8/8 translation segments, wrote `frame_index.csv`, and wrote `PROCESSING_SUMMARY.csv`, so no separate downstream frame-index bug was observed in this pass.

- [x] Repo-only: resume the blocked live OpenAI validation pass after `OPENAI_API_KEY` was restored
  Status: completed on 2026-04-16
  Current note: `OPENAI_API_KEY` was present in Process and User scope, so the live pass resumed. `Audio Mangler.ps1` completed a real OpenAI `it -> en` translation at `test-output\codex-openai-live-audio-20260416-193533`, and `AREA51\Validate-AudioManglerPackage.ps1` passed against that package. The same pass exposed the reproducible video-only HTTP 400 follow-up tracked above.

- [x] Repo-only: verify `Video Mangler.ps1` simulated OpenAI failure-mode parity after PR #11
  Status: completed on 2026-04-16
  Current note: Verified `MM_TEST_OPENAI_MODE=unauthorized`, `permission_denied`, `timeout`, `network`, `rate_limit`, and `server_error` against `Video Mangler.ps1`. For every case, `script_run.log`, `README_FOR_CODEX.txt`, `PROCESSING_SUMMARY.csv`, and the final console summary reported the expected category-specific provider text, operator note, next step, and partial-success status. No operator-facing audio/video mismatch was observed in this pass.

- [x] Repo-only: merge validated OpenAI error-classification and quota-messaging work from PR #11
  Status: completed on 2026-04-16
  Current note: Merged PR #11 into `main` after removing accidental tracked `dist/Audio Mangler.exe` and `dist/Video Mangler.exe` changes so the approved merge content stayed limited to `Audio Mangler.ps1`, `Video Mangler.ps1`, and `README.md`.

## Parity Summary

Open GitHub issues represented here:

- None currently open.
