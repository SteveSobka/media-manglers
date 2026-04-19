# TODO

This is the repo-visible issue-first board.

Rules:

- GitHub Issues are the canonical active work tracker.
- Every open GitHub issue must have a visible home here.
- If an open issue appears stale, partially fixed, or contradicted by the current workstream, keep it open here as `needs verification` until testing, validation, or operator review confirms the real status.
- Use `repo-only` only for active work that is intentionally not tracked by an open GitHub issue.
- Do not create fake backlog items just to fill the template.

## Active Workstreams

- [ ] Issue #22: Improve Hybrid operator UX, optional term profiles, early standalone preflight, and playlist safety
  Status: validated on hotfix branch; ready for PR review
  Current note: The `v0.7.2` hotfix branch now carries early loose-EXE Hybrid preflight failure before any download/transcription work, generic/default Hybrid behavior with optional `Protected Terms Profile` selection plus the seeded sim-racing profile, clearer OpenAI project/model/validation visibility during the run, operator-facing OpenAI text cost visibility, stronger playlist/expanded-run confirmation, replacement of the revoked short smoke/test-source guidance with the approved bounded Doc66 set, and the version bump/release notes refresh for `0.7.2`. Rig1 validation on the rebuilt package surface now includes loose-EXE early-failure proof, packaged German/French/English Hybrid video checks, the mixed single-plus-playlist confirmation interaction, PowerShell parse checks, `python -m unittest discover -s tests -p "test_*.py" -v`, `git diff --check`, and a fresh `Build-Exe.ps1 -App All` pass. DevBox CPU remains explicitly non-blocking for this release hotfix.

## Repo-Only Active Work

- [ ] Add durable regression coverage for Windows PowerShell 5.1 non-ASCII OpenAI transcript content
  Status: repo-only follow-up
  Current note: The `Video Mangler.ps1` bug is fixed and live-verified, but the repo still lacks permanent scripted coverage that proves UTF-8 transcript reads and UTF-8 request-byte sending stay correct for non-ASCII segments on Windows PowerShell 5.1.

- [ ] Validate real Local Whisper CUDA on a separate GPU-capable box before claiming CUDA success
  Status: repo-only follow-up
  Current note: The current 2026-04-18 developer box is now explicitly classified as CPU-only for Local Whisper by `Audio Mangler.ps1 -WhisperHealthCheck` and `Video Mangler.ps1 -WhisperHealthCheck`: selected Python interpreter `C:\Users\LocalDevAdmin\AppData\Local\Python\pythoncore-3.14-64\python.exe`, `torch 2.11.0+cpu`, torch CUDA `unavailable`, `cuda_available: false`, no detected GPU device names, and selected Local Whisper device `cpu`. That is no longer treated as a defect on this box. Real CUDA Local Whisper validation and sign-off still need to be rerun on a separate GPU-capable machine before the repo claims real CUDA success.

- [ ] Design a simple protected-terms profile authoring helper after the v0.7.2 hotfix lands
  Status: repo-only follow-up
  Current note: `v0.7.2` keeps the current JSON-backed Hybrid accuracy data format but re-frames it as optional `Protected Terms Profile` selection with generic/default mode plus a seeded sim-racing profile. The next scoped follow-up should help operators author or manage future profiles without turning this hotfix into a full profile-generator app.

## Recently Completed

- [x] Issue #20: Fix packaged Hybrid asset resolution and clean default console output
  Status: merged to main and closed on 2026-04-19
  Current note: Post-release Rig1 evidence showed a real packaged-run Hybrid failure after local transcription succeeded because the runtime tried to find `glossaries\de-en-sim-racing.json` without carrying or resolving that asset from the packaged surface. The accepted `v0.7.1` hotfix carried `python-core` plus `glossaries`, resolved runtime assets from the packaged surface instead of the repo/current working directory, improved loose-EXE package guidance, and cleaned up the default console output while keeping deeper helper chatter in `script_run.log`.

- [x] Issue #18: Post-merge cleanup for release packaging, repo layout, and docs
  Status: merged to main and closed on 2026-04-18
  Current note: PR `#19` merged the cleanup/release-hygiene pass to `main`, bumped the repo/app version to `0.7.0`, made the versioned ZIPs under `dist\release\` the canonical operator-facing artifacts, moved loose local-build EXEs to `dist\bin\`, moved tracked build/smoke/validation scripts into `tools\`, kept `Audio Mangler.ps1` and `Video Mangler.ps1` at repo root as the operator-facing wrapper sources, kept `glossaries\` as tracked runtime assets, and refreshed the repo/docs layout to match the current product. DevBox CPU validation is optional compatibility follow-up only and is not a blocker for this merged cleanup work.

- [x] Issue #16: Add Hybrid Accuracy processing path for multilingual media
  Status: merged to main and closed on 2026-04-18
  Current note: PR `#17` merged the Hybrid Accuracy v1 path into `main`. Rig1 acceptance evidence now includes longer accepted Hybrid runs for both wrappers on the approved German source, accepted validator/package parity on both real package outputs, and an accepted short French follow-on smoke. The current Hybrid default remains `gpt-4o-mini-2024-07-18`. Benchmark scoring/reporting integration, broader language support, broader glossary-profile support, and later GPU benchmarking remain follow-up work rather than merge blockers.

- [x] Track canonical repo-control docs so GitHub checkouts receive the same project context
  Status: completed on 2026-04-18
  Current note: Root cause was DevBox-local `.git/info/exclude` entries for `AGENTS.md`, `PROJECT_CHAT_PLAYBOOK.md`, and `governance/`, which kept those canonical control docs untracked and absent from both `origin/main` and `origin/wip/fix-estimate-stage-warning-2026-04-18`. This pass removed the local exclude trap on DevBox, promoted `AGENTS.md`, `PROJECT_CHAT_PLAYBOOK.md`, `governance/CURRENT_PROJECT_TRUTH.md`, `governance/LATEST_EVIDENCE_POINTER.md`, and the newly added `governance/FOREGROUND_VISUAL_WORK_PROTOCOL.md` into Git tracking, and normalized `AREA51/` casing in repo-control docs to match the actual tracked folder name and `.gitignore`. Verification for this fix is `git ls-tree` against the updated local branch and remote branch for the control-doc paths.

- [x] Add Hybrid-aware validator/package parity for the tracked package validation scripts
  Status: completed on 2026-04-18
  Current note: The tracked package validators now detect Hybrid packages from `PROCESSING_SUMMARY.csv`, require `translations\<lang>\validation_report.json` plus the key Hybrid summary columns (`lane_id`, `privacy_class`, `source_language`, `target_language`, `transcription_provider`, `transcription_model`, `translation_provider_name`, `translation_model`, and `translation_validation_status`), and accept `accepted`, `partial`, or `rejected` validation statuses from the Hybrid report instead of assuming Hybrid is always a plain success path. Revalidated in PASS 4 against the longer Rig1 Audio and Video Hybrid packages for `jfySUBLx8Ps`, where both tracked validators passed on the real output roots.

- [x] Add an operator-friendly Local Whisper runtime health check and classify this developer box correctly
  Status: completed on 2026-04-18
  Current note: `Audio Mangler.ps1`, `Video Mangler.ps1`, and `src/media_manglers/providers/whisper_local.py` now expose `-WhisperHealthCheck`, report the selected Python interpreter, Python version, torch version, torch CUDA version, `cuda_available`, detected GPU device names, selected Local Whisper device, and a plain-English classification of the current machine as `CPU-only for Local Whisper`, `GPU-capable for Local Whisper`, or `Local Whisper runtime misconfigured or uncertain`. Verified on the current 2026-04-18 developer box that both apps report `CPU-only for Local Whisper` using `C:\Users\LocalDevAdmin\AppData\Local\Python\pythoncore-3.14-64\python.exe`, `torch 2.11.0+cpu`, torch CUDA `unavailable`, `cuda_available false`, no detected GPU devices, and selected device `cpu`.

- [x] Fix the estimate-stage warning and harden Local Whisper runtime/device fallback visibility
  Status: completed on 2026-04-18
  Current note: `Audio Mangler.ps1`, `Video Mangler.ps1`, and `src/media_manglers/providers/whisper_local.py` now remove the invalid inline `if (...)` estimate expression that caused `Estimate step failed: The term 'if' is not recognized...`, reconfigure Python stdio safely for UTF-8, stop Whisper verbose transcript echoing that could trigger cp1252 encoding crashes, persist the requested/selected Whisper device plus fallback metadata in progress state, rebase adaptive runtime budgets when a GPU-planned Local Whisper run falls back to CPU, and surface `[GPU]`, `[CPU]`, and `[GPU->CPU]` status more clearly in the console/logs. Revalidated in this pass with PowerShell parse checks for both wrapper scripts, `python -m unittest discover -s tests -p "test_*.py" -v`, an estimate-path Audio Mangler validation on `AREA51\TestData\German_audio_short_45s.mp3 -TranslateTo en -WhisperModel medium` at `test-output\codex-audio-local-health-20260418-092500\` that no longer emitted the estimate-stage warning and passed `AREA51\Validate-AudioManglerPackage.ps1`, a real CPU Local transcript/translation run on the same output root that logged repeated `[CPU]` heartbeat lines plus `Whisper transcript completed using [CPU] cpu.`, and a focused replay of the observed GPU->CPU failure pattern on the same 45-second German fixture using temporary fake `torch`/`whisper` modules at `test-output\codex-gpu-fallback-replay-20260418-093500\`, which logged `Local Whisper switched from GPU to CPU ... runtime budget was rebased from 3m 33s to 4m 34s`, completed successfully on CPU, and passed `AREA51\Validate-AudioManglerPackage.ps1` with the synthetic three-segment transcript.

- [x] Stage the phased Python-core migration behind the current PowerShell wrappers
  Status: completed on 2026-04-18
  Current note: Phases 0, 1, 2, and 3 remain validated, and this pass stayed scoped to incremental wrapper-backed migration work instead of a broad Phase 4 rewrite. The branch now carries the repo-safe evidence pointer, the tracked Python helper CLI/contracts/utilities package, package README generation behind `media_manglers write-package-readme`, source/release artifact parity checks, improved Local operator prompts, faster default smoke fixtures for CPU-only validation, the adaptive Local Whisper timeout path with a separate stall watchdog, packaged EXE validation, and the one-time long German benchmark summary. Verified across the pass set with PowerShell parse checks, `python -m unittest discover -s tests -p "test_*.py"`, source-wrapper Local smoke/validator runs for both apps on `AREA51\TestData\1_min_test_Video.mp4`, `AREA51\Run-ArtifactParityChecks.ps1 -Surface Source`, clean `AREA51\Build-Exe.ps1 -App All`, extracted release-zip Local parity/validator runs for both packaged EXEs, packaged `-Version` checks at `0.6.1`, and the repo-tracked benchmark evidence in `docs/benchmarks/2026-04-17-german-to-english-transcription-benchmark.md`. Broader Phase 4 non-interactive pipeline migration is still intentionally not started or approved.

- [x] Verify longer CPU-only Local Whisper `large` behavior beyond the new warning safeguard
  Status: completed on 2026-04-18
  Current note: The one-time German-to-English benchmark documented in `docs/benchmarks/2026-04-17-german-to-english-transcription-benchmark.md` completed successful CPU-only Local `small`, `medium`, and `large` package runs on the 19m35s source `https://www.youtube.com/watch?v=jfySUBLx8Ps&list=PLPEYEQpJkUoCHM84_6N7Bg9bI-boFdr_6` with validator success for every successful lane. Local `large` used sample calibration, resolved adaptive budgets of `2h 02m 38s` for transcribe and `2h 08m 41s` for translate with a `4m 00s` stall watchdog, and completed end-to-end in `2h 20m 07.370s` without needing an explicit `-WhisperTimeoutSeconds` override. The local evidence root for this pass is `test-output/benchmark-20260417-german-url-comparison-20260417-203333/`.

- [x] Repo-only: replace the fixed Local Whisper timeout with adaptive runtime budgeting plus a separate stall watchdog
  Status: completed on 2026-04-17
  Current note: `Video Mangler.ps1`, `Audio Mangler.ps1`, and the tracked Python Whisper helper path now plan Local Whisper runtime per run from source duration, selected model, and CPU-vs-GPU capability, optionally refine long-run estimates with a short calibration transcription against the generated review audio, and keep the stall watchdog separate from the runtime budget. Interactive long Local runs now show a simple continue/switch-smaller/cancel prompt, `-WhisperTimeoutSeconds` now acts as an explicit override, and long-run `script_run.log` heartbeats now report elapsed time, estimated total time, estimated remaining time, adaptive runtime budget, and stall-watchdog state instead of implying that long silence always means failure. Verified in this pass with PowerShell parse checks for both wrapper scripts, `python -m unittest discover -s tests -p "test_*.py"`, `AREA51\Run-SmokeTest.ps1 -KeepTestOutput`, `AREA51\Run-AudioSmokeTest.ps1 -KeepTestOutput`, and a direct adaptive-timeout helper validation showing different Local Whisper budgets for 15-minute vs 90-minute CPU-only `large` runs and explicit override precedence. Packaged follow-up revalidation on the same branch then rebuilt both tracked EXEs with `AREA51\Build-Exe.ps1 -App All`, rechecked `dist\Video Mangler.exe -Version` plus `dist\Audio Mangler.exe -Version` at `0.6.1`, and completed extracted release-zip Local smoke/validator passes for both apps on `AREA51\TestData\1_min_test_Video.mp4`; packaged output showed `Local Whisper timeout mode: adaptive`, and packaged logs recorded the resolved `Local Whisper transcribe plan` plus separate stall-watchdog heartbeat lines.

- [x] Repo-only: tighten Local-mode operator prompts and make Codex smoke validation short-fixture-first
  Status: completed on 2026-04-17
  Current note: `Video Mangler.ps1` and `Audio Mangler.ps1` now ask interactive Local operators to choose `small`, `medium`, or `large` with rough CPU-only runtime tradeoffs instead of silently defaulting, using `medium` as the Enter/default choice for interactive Local runs while keeping scripted and `-NoPrompt` Local runs on the current accuracy-first `large` default. Interactive translation now asks a yes/no question first and defaults the follow-up target-language prompt to `en`. `AREA51\Run-SmokeTest.ps1` and `AREA51\Run-AudioSmokeTest.ps1` now prefer short local fixtures under `AREA51\TestData` before falling back to `test_media`, `test_audio`, or remote samples, and audio translation-to-English smoke coverage now prefers a short local-only `German_audio_short_45s.mp3` helper fixture when present. Verified in this pass with PowerShell parse checks for the changed `.ps1` files, default smoke/validator runs for both apps on the short local fixture path, interactive Enter/default prompt runs for both apps, `AREA51\Run-ArtifactParityChecks.ps1 -Surface Source`, `AREA51\Build-Exe.ps1 -App All`, and `AREA51\Run-ArtifactParityChecks.ps1 -Surface Release -SkipBuild`.

- [x] Repo-only: close the README/artifact trust gap before any merge-to-main decision
  Status: completed on 2026-04-17
  Current note: Added repo-safe `governance\LATEST_EVIDENCE_POINTER.md`; added `AREA51\Run-ArtifactParityChecks.ps1` plus `tests\fixtures\parity\local_artifact_hashes.json` so both apps now check `README_FOR_CODEX.txt`, `frame_index.csv`, `segment_index.csv`, `PROCESSING_SUMMARY.csv`, and `CODEX_MASTER_README.txt` against source-wrapper and extracted release-zip Local runs; and migrated only package README composition behind the tracked `media_manglers write-package-readme` CLI command while preserving wrapper UX, filenames, package layout, and release behavior.

- [x] Repo-only: prepare the v0.6.1 patch-release payload from current `main`
  Status: completed on 2026-04-17
  Current note: Bumped the repo/app version surfaces to `0.6.1`, refreshed `README.md` plus the packaged guide sources to match the current Local/AI behavior on `main`, added a dedicated `Command-line summary` section with the real current parameter surfaces, rebuilt both tracked executables plus `dist\release\Video-Mangler.exe`, `dist\release\Audio-Mangler.exe`, `Video-Mangler-v0.6.1.zip`, and `Audio-Mangler-v0.6.1.zip`, and revalidated source/exe `-Version` output at `0.6.1`. Verified in this pass that both release ZIPs contain the updated docs, `RELEASE_NOTES_v0.6.1.txt`, and `VERSION.txt = 0.6.1`; verified a Local default-behavior run for both apps without an explicit `-WhisperModel` and confirmed `Local Whisper model: large` in both logs; and rechecked the current AI allowlist path with Audio Mangler on this machine, where AI Public auto-detected `gpt-4o-mini-2024-07-18` and AI Private auto-detected `gpt-5-mini` plus `whisper-1`.

- [x] Repo-only: warn before likely long CPU-only Local Whisper `large` timeout surprises
  Status: completed on 2026-04-17
  Current note: `Video Mangler.ps1` and `Audio Mangler.ps1` now warn before transcription when Local mode is using Whisper `large` on CPU for media at or above 15 minutes, explicitly calling out the current `1800` second watchdog plus the practical fallback options (`GPU`, split media, or a smaller `-WhisperModel`). Verified in this pass by PowerShell parse of both scripts after the scoped edits. No full long-run completion rerun was performed.

- [x] Repo-only: raise Local mode Whisper defaults to accuracy-first `large`
  Status: completed on 2026-04-17
  Current note: `Video Mangler.ps1` and `Audio Mangler.ps1` now default Local mode to Whisper `large` when the operator did not explicitly choose a model, keep explicit `-WhisperModel` overrides available, log the resolved local model, and pass the detected source-language code into the local Whisper `translate` rerun for `-> en` translation. Reviewed the existing YouTube multi-track selector and kept it as-is because the current code already auto-selects provider-marked original/source audio when that metadata is available. Verified on this machine with a Local German video run at `test-output\codex-local-large-video-20260417-101452` and a Local foreign-language audio run at `test-output\codex-local-large-audio-short-20260417-101018`; both package validators passed, both per-package `script_run.log` files recorded `Local Whisper model: large`, and `rg "OpenAI"` against those logs returned no matches. Current caveat verified in the same pass: the longer `AREA51\TestData\German_audio.mp3` fixture (`19m35s`) hit the current `1800` second Whisper timeout on CPU with `large`, so the successful audio validation used a 45-second German clip extracted from the repo's German video fixture.

- [x] Repo-only: add safe OpenAI model auto-detection with strict Public/Private allowlists
  Status: completed on 2026-04-17
  Current note: `Video Mangler.ps1` and `Audio Mangler.ps1` now query `GET /v1/models` with the active key/project and only select from repo-approved model lists instead of choosing from every visible model. Verified on this machine that the current Public key only exposed the two approved Public translation models and the scripts auto-selected `gpt-4o-mini-2024-07-18`, while the current Private key exposed the approved Private set and the scripts auto-selected `gpt-5-mini` for translation plus `whisper-1` for transcription. Verified explicit Public override acceptance for `gpt-4.1-mini-2025-04-14`, and verified disallowed Public override failures in both apps when `gpt-5-mini` was requested.

- [x] Repo-only: refresh stale tracked packaged outputs and reconcile stale draft PRs after the v0.6.0 release
  Status: completed on 2026-04-17
  Current note: Confirmed the source/doc surfaces and the live GitHub `v0.6.0` release assets already reported `0.6.0`, but the tracked repo `dist\Video Mangler.exe` and `dist\Audio Mangler.exe` binaries on `main` were still stale `0.5.0` builds because the release prep commit updated `VERSION`, scripts, and docs without updating the tracked executables. Rebuilt both via `AREA51\Build-Exe.ps1 -App All`, revalidated source plus packaged `-Version` and launch banners at `0.6.0`, re-verified the comments prompt path with a controlled `yt-dlp` stub (`Enter`/`Y` requested comments, `N` skipped them), and closed stale draft PRs `#12` and `#5`. No corrective release was needed because the published `v0.6.0` GitHub release assets were already correct.

- [x] Repo-only: prepare the v0.6.0 release from current `main`
  Status: completed on 2026-04-17
  Current note: Confirmed local `main` matched `origin/main` at `dba8232`, bumped repo/app version surfaces to `0.6.0`, rebuilt both packaged executables and release zips, validated the canonical Video and Audio Local smoke paths, and verified the packaged docs/version files in both zips matched the tracked repo copies.

- [x] Repo-only: validate AI Private end-to-end with the working Private transcription key path
  Status: completed on 2026-04-17
  Current note: Verified the current Codex/child PowerShell process can see `OPENAI_API_KEY_PRIVATE`, confirmed AI Private still resolves `Private -> OPENAI_API_KEY_PRIVATE` with `OPENAI_API_KEY` only as a legacy fallback, confirmed the scripted transcription request still uses `POST /v1/audio/transcriptions` with model `whisper-1` and multipart file upload, fixed a `List[object]` to array conversion bug in both OpenAI transcription artifact paths, and reran `VIDEO AI Private English`, `VIDEO AI Private Foreign`, `AUDIO AI Private English`, and `AUDIO AI Private Foreign` successfully.

- [x] Repo-only: simplify Video Mangler and Audio Mangler to Local vs AI processing modes
  Status: completed on 2026-04-16
  Current note: Added `docs/plans/2026-04-16-ai-vs-local-mode-simplification.md`, promoted `-ProcessingMode Local|AI` to the primary operator-facing control in both apps, kept `TranslationProvider` as compatibility-only, updated package/operator docs, added `AREA51\Run-AI-Local-Mode-Matrix.ps1`, and verified the matrix evidence that was possible on this machine on 2026-04-16. Verified passes in that pass: Video Local English, Video Local foreign, Audio Local English, Audio Local foreign, Audio AI Public English, and Video AI Public foreign. AI Private end-to-end was validated in the follow-up pass on 2026-04-17.

- [x] Repo-only: document OpenAI integration, Private/Public guidance, and safe key selection defaults
  Status: completed on 2026-04-16
  Current note: `README.md`, `docs/guides/VIDEO_MANGLER.txt`, and `docs/guides/AUDIO_MANGLER.txt` now explain that OpenAI API use is optional, separate from ChatGPT subscriptions, and depends on API billing/credits. Both scripts now default to Private via `OPENAI_API_KEY_PRIVATE`, require an explicit `-OpenAiProject Public` choice for `OPENAI_API_KEY_PUBLIC`, and keep `OPENAI_API_KEY` as a legacy Private fallback for older setups.

- [x] Repo-only: change the interactive YouTube comments prompt to default Yes on Enter
  Status: completed on 2026-04-16
  Current note: `Video Mangler.ps1` and `Audio Mangler.ps1` now show `If comments are available for a YouTube source, save them in the package too? (Y/n):`, and pressing Enter accepts comments by default. The README and operator guides were updated to match the real behavior.

- [x] Repo-only: align Audio Mangler with the live UTF-8-safe OpenAI path and diagnostics behavior
  Status: completed on 2026-04-16
  Current note: `Audio Mangler.ps1` now reads transcript JSON as UTF-8, sends OpenAI translation bodies as UTF-8 bytes, writes OpenAI diagnostics parity files, and uses the same PowerShell 5.1-safe Argos JSON handling as `Video Mangler.ps1`. Local English and foreign rows passed after the BOM fix. AI Public also passed with local transcription plus OpenAI translation. AI Private currently stops only at the external transcription-permission blocker noted above.

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

- #22 `Improve Hybrid operator UX, optional term profiles, early standalone preflight, and playlist safety`
