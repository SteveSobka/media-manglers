# 2026-04-20 Brooklands source-transcript follow-up

## Purpose and scope

This follow-up pass addresses GitHub issue `#34`:
`Investigate Brooklands source-transcript recall weakness in local benchmark evidence`.

The scope of this pass stayed narrow:

- preserve the already-fixed Hybrid translation-side boundary from issue `#28`
- inspect preserved benchmark evidence first
- test whether a narrow source-language hint improved the raw transcript
- clarify benchmark reporting so raw/source transcript substitution is not
  confused with translation-side corruption
- rerun only the minimum Brooklands-focused local comparison needed on Rig1

This was not a long-suite, shadow-set, playlist, or Video parity pass.

## Evidence-backed diagnosis

Preserved evidence roots reviewed first:

- `C:\DATA\TEMP\CODEX\mm-short-pilot-20260419`
- `C:\DATA\TEMP\CODEX\mm-brooklands-fix-20260420-2`

What that evidence showed:

- The issue-28 Hybrid fix worked. `Brooklands -> Brooklyn` no longer appears in
  the validated Hybrid translation lanes.
- The remaining warning is in the raw/source transcript evidence for the
  Brooklands German control.
- The local medium lanes are the weak point:
  - preserved `local-medium-gpu` evidence used `Brooklyns`
  - preserved `local-medium-cpu` evidence also missed literal `Brooklands`
- Earlier preserved evidence suggested stronger source recall from
  `local-large-gpu` and `ai-private-whisper-1-gpt-5-mini`, but that was
  historical evidence, not yet a new default recommendation.

This means the remaining warning is source-transcript-side, not a reopened
translation defect.

## Narrow probe outcome

Before changing tracked code, the pass ran a direct Brooklands probe with an
explicit German source-language hint:

```powershell
& '.\Audio Mangler.ps1' -InputUrl 'https://www.youtube.com/watch?v=hNaUbuWL8MI' -InputFolder 'C:\DATA\TEMP\CODEX\brooklands-language-probe-20260420\input' -OutputFolder 'C:\DATA\TEMP\CODEX\brooklands-language-probe-20260420\output' -ProcessingMode Local -TranslateTo en -WhisperModel medium -WhisperDevice GPU -Language de -NoPrompt -SkipEstimate -HeartbeatSeconds 15
```

That probe still produced the source-side `Brooklyns` substitution in the raw
transcript. The hint did not fix the issue on Rig1, so this pass did not change
normal transcription behavior or silently rewrite raw transcripts.

## Reporting/scoring change

This pass landed a benchmark-reporting clarification instead of fabricating a
source-transcript "fix".

The benchmark reporter now distinguishes:

- source-transcript substitution
- source-transcript omission
- translation-side substitution
- translation-side omission

New additive benchmark row fields include:

- `named_entity_source_substitution_count`
- `named_entity_translation_substitution_count`
- `named_entity_source_missing_count`
- `named_entity_translation_missing_count`
- `brooklands_source_variant_flag`

The JSON `named_entity_checks` payload now also carries:

- `source_bad_form_matches`
- `translation_bad_form_matches`
- `source_issue`
- `translation_issue`

This keeps raw transcript integrity intact and makes it much harder to confuse a
source-transcript warning with the already-fixed Hybrid translation defect.

## Focused rerun matrix

Focused output root:

- `C:\DATA\TEMP\CODEX\mm-brooklands-source-recall-20260420`

Focused benchmark commands:

```powershell
& '.\tools\benchmarks\Run-BenchmarkSuite.ps1' -SuiteManifestPath '.\tools\benchmarks\manifests\canonical-short.json' -LaneManifestPath '.\tools\benchmarks\manifests\benchmark-lanes-v1.json' -AppSurface Audio -LaneId @('local-medium-gpu','local-large-gpu') -SourceId 'de-brooklands-hNaUbuWL8MI' -OutputRoot 'C:\DATA\TEMP\CODEX\mm-brooklands-source-recall-20260420' -HeartbeatSeconds 15 -SkipEstimate
& '.\tools\benchmarks\Run-BenchmarkSuite.ps1' -SuiteManifestPath '.\tools\benchmarks\manifests\canonical-short.json' -LaneManifestPath '.\tools\benchmarks\manifests\benchmark-lanes-v1.json' -AppSurface Audio -LaneId 'local-medium-cpu' -SourceId 'de-brooklands-hNaUbuWL8MI' -OutputRoot 'C:\DATA\TEMP\CODEX\mm-brooklands-source-recall-20260420' -HeartbeatSeconds 15 -SkipEstimate
python .\tools\benchmarks\benchmark_report.py --run-root 'C:\DATA\TEMP\CODEX\mm-brooklands-source-recall-20260420' --suite-manifest '.\tools\benchmarks\manifests\canonical-short.json' --lane-manifest '.\tools\benchmarks\manifests\benchmark-lanes-v1.json' --lane-ids 'local-medium-gpu,local-medium-cpu,local-large-gpu' --source-ids 'de-brooklands-hNaUbuWL8MI'
```

## Focused results

- `local-medium-gpu`
  - completed successfully
  - benchmark status: `warning`
  - raw/source transcript still substituted the Brooklands entity
  - preserved variant in raw evidence: `Brooklyns`
  - `brooklands_source_variant_flag = True`
  - no translation-side Brooklands corruption was flagged

- `local-medium-cpu`
  - completed successfully
  - benchmark status: `warning`
  - raw/source transcript still substituted the Brooklands entity
  - preserved variant in raw evidence: `Brooklynz`
  - `brooklands_source_variant_flag = True`
  - no translation-side Brooklands corruption was flagged

- `local-large-gpu`
  - attempted as the preferred comparison lane
  - did not complete within the current adaptive runtime budget on this source
  - benchmark status: `rejected`
  - this pass did not broaden into a timeout-budget fix, so `local-large-gpu`
    is not promoted here as a settled Brooklands-sensitive recommendation on
    Rig1

## Interpretation

- The remaining Brooklands warning is real, but it is a raw/source transcript
  problem rather than a reopened Hybrid translation defect.
- A direct `-Language de` probe did not fix the medium-model recall on Rig1.
- This branch preserves raw transcript integrity and makes the benchmark output
  say what actually happened:
  - source transcript substituted the entity
  - translation-side Brooklands corruption stayed fixed
- A later pass can still pursue a narrower product-side transcription
  improvement, a lane recommendation refresh, or a separate timeout-budget
  investigation if warranted.
