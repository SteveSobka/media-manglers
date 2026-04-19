# Python Core Migration Plan - 2026-04-17

## Summary

- Goal: move Media Manglers toward a hybrid architecture where Python owns the cross-platform core and PowerShell remains the Windows-friendly wrapper/operator entry point.
- Guardrails: do not retire the current PowerShell path, do not break the existing Windows EXE/distributable path, and only advance phases after validation passes.
- Current repo reality: `Video Mangler.ps1` and `Audio Mangler.ps1` are large sibling wrappers with heavy overlap, and the local Whisper / Argos paths already depend on Python today through temporary helper scripts.

## Execution Status For This Pass

- Completed and validated in this pass:
  - Phase 0
  - Phase 1
  - Phase 2
  - Phase 3
  - Phase 4 gate-closure prework:
    - repo-safe governance pointer fix
    - fixture-backed broader artifact parity coverage
    - one low-risk package README artifact step behind `media_manglers`
- Not started in this pass:
  - broader Phase 4 pipeline migration
- Follow-up wrapper/harness tightening kept out of Phase 4:
  - interactive Local runs now prompt for Whisper model choice instead of silently surprising operators
  - routine smoke validation now prefers short local fixtures so CPU-only Codex passes stay practical
- Current stop rationale:
  - the helper-boundary migration and release-sidecar strategy remain proven for source-wrapper runs and extracted release-zip runs
  - broader artifact parity now covers package README, frame index, segment index, processing summary, and master README for both apps
  - only package README composition moved behind the tracked CLI, with the PowerShell fallback preserved
  - the next move would still require explicit approval plus additional parity discipline before changing more non-interactive pipeline ownership

## Current Findings

- `Video Mangler.ps1` and `Audio Mangler.ps1` each expose `129` functions, with `118` shared by name and purpose.
- The current Windows release path is still PowerShell-first: `tools/release/Build-Exe.ps1` builds the wrappers with `ps2exe` and packages docs plus release zips.
- The repo-governance mismatch is now resolved by a repo-safe `governance/LATEST_EVIDENCE_POINTER.md` that records where local evidence lives without redefining repo truth.
- Broader artifact parity now lives in:
  - `tools/validation/Run-ArtifactParityChecks.ps1`
  - `tests/fixtures/parity/local_artifact_hashes.json`
- `README_FOR_CODEX.txt` is now generated through the tracked `media_manglers write-package-readme` command in both wrappers, while preserving the existing PowerShell fallback path.
- `segment_index.csv` cannot use a fixed-content hash reliably because it reflects live Whisper transcript output, so the parity harness validates schema plus transcript-row consistency for that artifact instead of pinning one transcript text snapshot.
- Portability blockers currently include:
  - hardcoded Windows path defaults (`C:\...`, `D:\...`)
  - `Invoke-Item` / Explorer behavior
  - child `powershell -NoProfile -ExecutionPolicy Bypass` calls in smoke/matrix scripts
  - Windows-oriented tool discovery for FFmpeg / yt-dlp / Python
- The most natural first Python seam is the helper logic that already runs in Python today:
  - Whisper environment probing
  - Whisper transcript / translate-to-English helpers
  - Argos probe / install / translate helpers

## Approved Architecture

- PowerShell stays as the operator-facing entry point on Windows for this migration.
- Python is introduced as a tracked package with `pyproject.toml` and `src/media_manglers/`.
- PowerShell-to-Python integration uses a stable CLI contract first.
- The wrapper-side Python launcher rule is:
  1. explicit configured interpreter path if available
  2. else `python`
  3. else `py -3`
  4. else fail with clear operator guidance

## Phase Plan

### Phase 0

- Create the branch and promote this plan into the repo.
- Update `TODO.md` at pass start.
- Add the Python package/test skeleton with no runtime behavior change yet.

### Phase 1

- Move only already-Python-backed helper logic into tracked Python modules.
- Keep the current PowerShell wrappers in charge of prompting, orchestration, logging, and compatibility behavior.
- Use the Python CLI contract for source runs, with a safe compatibility fallback so current EXE/distributable assumptions are not broken during the transition.

### Phase 2

- Move shared portable transcript / artifact / helper utilities into the Python package where that does not alter operator UX.
- Add Python-side tests for request/result contracts and the migrated helper behavior.

### Phase 3

- Define and validate how the Python core is carried alongside the current PowerShell/EXE path.
- Preserve the existing standalone wrapper path while introducing a sidecar packaging path for the new Python core.
- Current chosen release strategy for this pass:
  - release zips carry `app\python-core\src\media_manglers`
  - the PowerShell wrappers continue to fall back to the legacy inline helper path when that sidecar is absent
  - standalone wrapper EXEs therefore remain compatible during the transition instead of being forced onto the new sidecar immediately
- Validation completed in this pass:
  - `tools\release\Build-Exe.ps1 -App All` passed
  - both release ZIPs contain the tracked `python-core` files and exclude `__pycache__` / `.pyc`
  - extracted release-zip runs for both packaged EXEs completed Local smoke/validator passes while invoking `python -m media_manglers`

### Phase 4

- Only if Phases 1-3 remain validated and trustworthy, start moving broader non-interactive pipeline logic into Python for both apps.
- Stop rather than forcing a large rewrite without parity evidence.
- This pass intentionally stopped after one low-risk artifact step:
  - `README_FOR_CODEX.txt` generation now runs through `media_manglers write-package-readme`
  - wrapper UX, filenames, package layout, and release behavior stayed unchanged
- Current gate for any next Phase 4 pass:
  - keep `tools/validation/Run-ArtifactParityChecks.ps1` green for both source-wrapper and extracted release-zip runs
  - move only one additional non-interactive step at a time
  - stop if transcript-derived parity becomes unclear or release behavior changes

## Validation Gates

- End every phase with the most relevant parse/tests/smoke/build checks available for that phase.
- Keep the PowerShell validators as acceptance checks wherever possible:
  - `tools\validation\Validate-VideoToCodexPackage.ps1`
  - `tools\validation\Validate-AudioManglerPackage.ps1`
- Current gate-closing validation now also includes:
  - `python -m unittest discover -s tests -p "test_*.py"`
  - `tools\validation\Run-ArtifactParityChecks.ps1 -Surface Source`
  - `tools\release\Build-Exe.ps1 -App All`
  - `tools\validation\Run-ArtifactParityChecks.ps1 -Surface Release -SkipBuild`
- Do not claim parity without evidence from current scripts, validators, or build outputs.

## Current Risks

- The current standalone EXE artifacts do not yet carry a tracked Python core beside them.
- Broader non-interactive pipeline ownership is still unproven beyond the newly migrated README artifact step.
- Current local-mode behavior already depends on external Python packages, so any new Python-core path must stay at least as transparent and recoverable as the current operator experience.
