# 2026-04-20 canonical short-suite pilot

## Purpose and scope

This pass is the first tracked proof of the standardized benchmark/reporting
workflow. It uses the approved Doc66 motorsport / sim-racing short set, the
tracked benchmark manifests, and the new benchmark runner/reporting tools.

This is a bounded pilot, not a full long-suite bakeoff.

- Primary benchmark surface: `Audio Mangler`
- Suite: `canonical-short`
- Raw artifacts: preserved under the local Rig1 benchmark/evidence root, not
  tracked in Git
- Playlists: not used
- Revoked short sources: not used

## Canonical short sources in this pilot

- `en-control-1aA1WGON49E`
- `de-brooklands-hNaUbuWL8MI`
- `de-hockenheimring-7_u8Qj78cA0`
- `fr-lemans-XRka52Y3kyA`
- `ja-suzuka-WPm2N93SmTA`
- `es-velocidad-5OspljwLkDQ`
- `it-iracing-Xe6AgUkZmog`
- `zh-gt7-fJ7V53jFrVc`

## Lane matrix used

Full canonical short suite:

- `local-medium-gpu`
- `hybrid-private-medium-gpt-4o-mini`

Brooklands control cross-lane comparison:

- `local-medium-cpu`
- `local-large-gpu`
- `hybrid-public-medium-gpt-4o-mini`
- `hybrid-public-medium-gpt-4.1-mini`
- `hybrid-private-medium-gpt-5-mini`
- `ai-private-whisper-1-gpt-5-mini`

Deferred in this pilot:

- `local-large-cpu`
- `hybrid-private-large-gpt-5-mini`
- `ai-private-gpt-4o-mini-transcribe-gpt-5-mini`
- `ai-private-gpt-4o-transcribe-gpt-5-mini`
- broader `Video Mangler` parity benchmarking

## Current pilot winners

- Best current local lane: `local-medium-gpu`
  - average score `85.0`
  - average runtime `138.091s`
  - completed short-suite rows `8`
- Best current accuracy lane: `local-medium-gpu`
  - average score `85.0`
  - average runtime `138.091s`
  - completed short-suite rows `8`
- Best current speed lane: `hybrid-private-medium-gpt-4o-mini`
  - average score `80.879`
  - average runtime `114.22s`
  - completed short-suite rows `8`

## What this pilot proves

- The repo now has tracked benchmark manifests for canonical short, canonical
  long, and technical-terminology shadow suites.
- The repo now has a tracked benchmark runner plus aggregation/report outputs:
  `benchmark-summary.csv`, `benchmark-results.json`, and
  `benchmark-summary.md`.
- Benchmark rows now carry benchmark-friendly metadata such as app/version,
  duration, requested lane configuration, requested/actual Whisper device,
  run/runtime metadata, validation/cost signals, and named-entity scoring.
- Generic/no-profile behavior is the current benchmark baseline. The pilot did
  not silently apply a sim-racing protected-terms profile to unrelated sources.
- Audio-first benchmarking is practical for the recurring language suite because
  it keeps transcript/translation quality visible without video/frame noise.

## Current benchmark findings

- `local-medium-gpu` is the best current local and best current accuracy lane
  on Rig1 in this bounded pilot.
- `hybrid-private-medium-gpt-4o-mini` is the fastest lane among the lanes with
  full short-suite coverage in this pilot.
- The Brooklands control still flags `Brooklands -> Brooklyn` corruption in the
  current Hybrid `gpt-4o-mini` / `gpt-4.1-mini` translation lanes:
  - `hybrid-public-medium-gpt-4o-mini`
  - `hybrid-public-medium-gpt-4.1-mini`
  - `hybrid-private-medium-gpt-4o-mini`
- `hybrid-private-medium-gpt-5-mini` was attempted, but the current Private
  project on Rig1 could not use that model. The pilot records that as rejected
  evidence, not as a silent fallback.
- `ai-private-whisper-1-gpt-5-mini` completed the Brooklands control cleanly
  enough to score a warning-level result, but it has only Brooklands-only pilot
  coverage so it is not the current default recommendation.

## Command record

The exact executed commands for each row are preserved in the per-run
`lane-meta.json` files under the local evidence root. Repo-relative reproduction
examples for this pilot shape are:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File '.\tools\benchmarks\Run-BenchmarkSuite.ps1' -SuiteManifestPath '.\tools\benchmarks\manifests\canonical-short.json' -LaneManifestPath '.\tools\benchmarks\manifests\benchmark-lanes-v1.json' -AppSurface Audio -LaneId 'local-medium-gpu' -OutputRoot '<temp-benchmark-root>' -HeartbeatSeconds 15 -SkipEstimate
powershell -NoProfile -ExecutionPolicy Bypass -File '.\tools\benchmarks\Run-BenchmarkSuite.ps1' -SuiteManifestPath '.\tools\benchmarks\manifests\canonical-short.json' -LaneManifestPath '.\tools\benchmarks\manifests\benchmark-lanes-v1.json' -AppSurface Audio -LaneId 'hybrid-private-medium-gpt-4o-mini' -OutputRoot '<temp-benchmark-root>' -HeartbeatSeconds 15 -SkipEstimate
& '.\tools\benchmarks\Run-BenchmarkSuite.ps1' -SuiteManifestPath '.\tools\benchmarks\manifests\canonical-short.json' -LaneManifestPath '.\tools\benchmarks\manifests\benchmark-lanes-v1.json' -AppSurface Audio -LaneId @('local-medium-cpu','local-large-gpu','hybrid-public-medium-gpt-4o-mini','hybrid-public-medium-gpt-4.1-mini','hybrid-private-medium-gpt-5-mini','ai-private-whisper-1-gpt-5-mini') -SourceId 'de-brooklands-hNaUbuWL8MI' -OutputRoot '<temp-benchmark-root>' -HeartbeatSeconds 15 -SkipEstimate
python .\tools\benchmarks\benchmark_report.py --run-root '<temp-benchmark-root>' --suite-manifest '.\tools\benchmarks\manifests\canonical-short.json' --lane-manifest '.\tools\benchmarks\manifests\benchmark-lanes-v1.json' --lane-ids 'local-medium-gpu,local-medium-cpu,local-large-gpu,hybrid-public-medium-gpt-4o-mini,hybrid-public-medium-gpt-4.1-mini,hybrid-private-medium-gpt-4o-mini,hybrid-private-medium-gpt-5-mini,ai-private-whisper-1-gpt-5-mini' --source-ids 'en-control-1aA1WGON49E,de-brooklands-hNaUbuWL8MI,de-hockenheimring-7_u8Qj78cA0,fr-lemans-XRka52Y3kyA,ja-suzuka-WPm2N93SmTA,es-velocidad-5OspljwLkDQ,it-iracing-Xe6AgUkZmog,zh-gt7-fJ7V53jFrVc' --include-deferred
```

## Interpretation rules

- Accuracy outranks runtime.
- The benchmark summary is additive evidence, not a replacement for raw
  package outputs.
- The short-suite pilot is enough to guide the next passes, but it does not
  replace the future canonical long-suite refresh.
- The Brooklands named-entity defect remains visible on purpose. The benchmark
  framework is supposed to make that kind of corruption harder to miss, not
  smoother to explain away.
