Media Manglers Benchmark Guide
==============================

Purpose
-------
The benchmark framework turns repeatable motorsport/sim-racing benchmark runs
into compareable CSV, JSON, and Markdown outputs. It is separate from the smoke
and validator scripts.

Key docs
--------
- BENCHMARK_PROGRAM.md
- BENCHMARK_RESULTS_SCHEMA.md

Tracked suite manifests
-----------------------
- tools\benchmarks\manifests\canonical-short.json
- tools\benchmarks\manifests\canonical-long.json
- tools\benchmarks\manifests\technical-terminology-shadow.json
- tools\benchmarks\manifests\benchmark-lanes-v1.json

Tracked benchmark tools
-----------------------
- tools\benchmarks\Run-BenchmarkSuite.ps1
- tools\benchmarks\benchmark_report.py

Normal workflow
---------------
1. Pick a suite manifest and the lanes you want to run.
2. Run the benchmark suite into a dedicated output root.
3. Keep the raw package outputs, lane-meta.json files, and logs.
4. Use the generated benchmark-summary.csv / benchmark-results.json /
   benchmark-summary.md to compare lanes over time.

Bounded benchmark rules
-----------------------
- Use only approved single-video sources for bounded short passes.
- Do not use playlists for bounded short benchmark passes.
- Do not use revoked short sources.

Current benchmark status
------------------------
- Latest canonical short benchmark summary:
  docs\benchmarks\2026-04-20-short-suite-pilot.md
- Latest Brooklands defect follow-up:
  docs\benchmarks\2026-04-20-brooklands-hybrid-followup.md
- Latest Brooklands source-transcript follow-up:
  docs\benchmarks\2026-04-20-brooklands-source-transcript-followup.md
- Latest canonical long benchmark status:
  defined in manifests; full long-suite rerun not yet completed under the new
  benchmark-reporting framework

Current lane guidance
---------------------
- Best current local lane: local-medium-gpu
- Best current accuracy lane: local-medium-gpu
- Best current speed lane: hybrid-private-medium-gpt-4o-mini

Important caveats
-----------------
- Accuracy outranks runtime.
- Benchmark summaries do not replace raw artifacts.
- AI Private transcription is still cleanly wired to whisper-1 in current main.
- Raw benchmark packages and lane-meta.json files live in the local evidence/temp
  root used for the pass; they are not tracked in Git.
- The 2026-04-20 short-suite pilot intentionally preserved the original
  Brooklands -> Brooklyn Hybrid defect evidence, and the focused issue-28
  follow-up tracks the branch-level fix proof separately.
- The issue-28 fix removes the Hybrid translation-side Brooklands corruption in
  the focused rerun lanes.
- Issue #34 is a separate raw/source transcript problem. On Rig1, the focused
  Brooklands follow-up still shows source-side substitution on the local medium
  lanes (`Brooklyns` on GPU and `Brooklynz` on CPU in the preserved raw
  evidence). A direct `-Language de` probe did not lift the medium-lane recall.
- The 2026-04-20 short-suite pilot attempted hybrid-private-medium-gpt-5-mini,
  but the current Rig1 Private project could not use that model.
- The focused issue-34 comparison run also showed that `local-large-gpu` did
  not finish within the current adaptive runtime budget on this source, so it
  is not yet a settled Brooklands-sensitive recommendation on Rig1.
- The technical terminology shadow set exists because racing-history clips alone
  will not catch SimHub / Crew Chief / UI vocabulary regressions.
