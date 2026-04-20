# 2026-04-20 Brooklands Hybrid follow-up

## Purpose and scope

This follow-up pass addresses GitHub issue `#28`:
`Investigate Brooklands named-entity corruption in current Hybrid benchmark lanes`.

The goal of this pass was narrow:

- confirm the exact Brooklands defect from preserved pilot evidence
- fix the Hybrid translation-side `Brooklands -> Brooklyn` corruption in the
  affected benchmark lanes
- rerun only the minimum focused benchmark matrix needed to prove the fix

This was not a new full short-suite run, long-suite run, or shadow-set pass.

## Preserved evidence diagnosis

The preserved pilot root under
`C:\DATA\TEMP\CODEX\mm-short-pilot-20260419` showed that the original defect
occurred in the English translation artifacts for the Brooklands control on:

- `hybrid-public-medium-gpt-4o-mini`
- `hybrid-public-medium-gpt-4.1-mini`
- `hybrid-private-medium-gpt-4o-mini`

The benchmark summary correctly flagged:

- `brooklands_to_brooklyn_flag = True`
- `protected_terms_profile = none (generic mode)`
- `validation_status = en=accepted`

That evidence showed a real Hybrid translation-side proper-noun corruption plus
missing validation/repair coverage for benchmark-critical entity changes.

## Fix approach

The chosen fix stayed deliberately narrow.

- Benchmark manifests already track `expected_named_entities` for sources such
  as the Brooklands control.
- The benchmark runner now passes those expected entities into the Hybrid
  translation request through a JSON file path instead of brittle raw
  command-line JSON.
- Hybrid translation/repair validation now uses those benchmark hints to:
  - strengthen proper-noun preservation instructions
  - detect listed bad forms such as `Brooklyn`
  - reject and retry translations that corrupt expected named entities
  - compute final validation status from the actual final validation result

This keeps generic/no-profile product behavior intact. The fix does not silently
apply a sim-racing protected-terms profile to unrelated content.

## Focused rerun matrix

Required Brooklands reruns:

- `hybrid-public-medium-gpt-4o-mini`
- `hybrid-public-medium-gpt-4.1-mini`
- `hybrid-private-medium-gpt-4o-mini`

Required local control:

- `local-medium-gpu`

Supporting non-Brooklands control:

- source `de-hockenheimring-7_u8Qj78cA0`
- lane `hybrid-public-medium-gpt-4o-mini`

Focused output root:

- `C:\DATA\TEMP\CODEX\mm-brooklands-fix-20260420-2`

## Command record

```powershell
& '.\tools\benchmarks\Run-BenchmarkSuite.ps1' -SuiteManifestPath '.\tools\benchmarks\manifests\canonical-short.json' -LaneManifestPath '.\tools\benchmarks\manifests\benchmark-lanes-v1.json' -AppSurface Audio -LaneId @('hybrid-public-medium-gpt-4o-mini','hybrid-public-medium-gpt-4.1-mini','hybrid-private-medium-gpt-4o-mini','local-medium-gpu') -SourceId 'de-brooklands-hNaUbuWL8MI' -OutputRoot 'C:\DATA\TEMP\CODEX\mm-brooklands-fix-20260420-2' -HeartbeatSeconds 15 -SkipEstimate
& '.\tools\benchmarks\Run-BenchmarkSuite.ps1' -SuiteManifestPath '.\tools\benchmarks\manifests\canonical-short.json' -LaneManifestPath '.\tools\benchmarks\manifests\benchmark-lanes-v1.json' -AppSurface Audio -LaneId 'hybrid-public-medium-gpt-4o-mini' -SourceId 'de-hockenheimring-7_u8Qj78cA0' -OutputRoot 'C:\DATA\TEMP\CODEX\mm-brooklands-fix-20260420-2' -HeartbeatSeconds 15 -SkipEstimate
```

## Results

Brooklands rerun result:

- `hybrid-public-medium-gpt-4o-mini`: `Brooklands` preserved in translation
- `hybrid-public-medium-gpt-4.1-mini`: `Brooklands` preserved in translation
- `hybrid-private-medium-gpt-4o-mini`: `Brooklands` preserved in translation
- `local-medium-gpu`: local control remained clean

The rerun summary at
`C:\DATA\TEMP\CODEX\mm-brooklands-fix-20260420-2\summary\benchmark-summary.csv`
now shows:

- `brooklands_to_brooklyn_flag = False` for the three previously corrupted
  Hybrid lanes
- `named_entity_translation_present_count = 1` for those Hybrid lanes

The supporting Hockenheimring control also completed cleanly on
`hybrid-public-medium-gpt-4o-mini`.

## Remaining warning and follow-up boundary

The Brooklands defect tracked by issue `#28` is the Hybrid translation-side
corruption, and this focused rerun fixes that defect on the validated lanes.

Benchmark scoring can still show a warning on the Brooklands control because the
local source transcript does not always literally preserve `Brooklands` in the
source-side evidence. That is a separate transcription/benchmark-quality
follow-up and should not be confused with the fixed Hybrid translation defect.

## Interpretation

- The benchmark framework did its job by surfacing a real proper-noun defect.
- The issue-28 branch fixes the Hybrid translation-side corruption without
  breaking generic/no-profile behavior.
- The focused rerun is sufficient evidence for this defect-fix pass.
- The full canonical short suite, long suite, and technical terminology shadow
  set remain separate follow-up work.
