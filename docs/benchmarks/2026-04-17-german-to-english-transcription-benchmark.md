# 2026-04-17 German-to-English transcription benchmark

## Purpose and scope

This pass was a one-time longer comparison run for operator guidance, not a simple pass/fail smoke test. The goal was to run the same German source through the current five relevant Audio Mangler lanes, preserve the normal package output for each successful lane, and document the speed, quality, and usability tradeoffs plainly enough to guide later operator choices.

This benchmark does **not** promote the benchmark URL into a default smoke-test input, default validator input, recurring fixture, or future long-test source. It was used only for this explicit evidence pass.

## Exact source used for this pass

- Source URL: `https://www.youtube.com/watch?v=jfySUBLx8Ps&list=PLPEYEQpJkUoCHM84_6N7Bg9bI-boFdr_6`
- Source title: `Crew Chief & Meine Settings | Die Basics`
- Source id: `jfySUBLx8Ps`
- Source duration: `19m 35s` (`1175` seconds)
- Target translation language: `en`
- App used: `Audio Mangler.ps1`
- Branch used for this pass: `wip/python-core-phased-migration-2026-04-17`
- Local evidence root for this pass: `test-output/benchmark-20260417-german-url-comparison-20260417-203333/`

## Environment notes

- OS: Windows 11 Business 64-bit, build `26100`
- Python: `3.14.3`
- `yt-dlp`: `2026.03.17`
- `ffmpeg`: `N-123778-g3b55818764-20260331`
- `torch`: `2.11.0+cpu`
- GPU reality on this machine: CPU-only for Local Whisper in this pass
- CUDA check: `cuda_available=False`, `cuda_device_count=0`
- OpenAI credential state in this pass:
  - AI Public key available
  - AI Private key available
- Package validation path used after each lane: `AREA51\Validate-AudioManglerPackage.ps1`

## Caption availability and comparison limits

`yt-dlp --list-subs --no-playlist` reported auto captions for `de-orig` and `en`, but no manual subtitle tracks. The `de-orig` auto-caption track downloaded successfully and was used as a rough practical comparison reference for the German transcript outputs. The `en` auto-caption track could not be downloaded reliably in this pass because repeated attempts returned `HTTP Error 429: Too Many Requests`.

That means the transcript comparison in this document is intentionally practical, not scientific. The rough `de-orig` similarity score below is useful only for lane-to-lane relative comparison in this pass. It is not a ground-truth accuracy score.

## Run matrix

All five requested lanes were attempted, and all five completed with package success plus validator success.

| Lane | Transcript path | Translation path | Status | Wall clock | Approx speed vs 19m35s source | Segments | Output files | Output size | Package status | Notes |
| --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | --- | --- |
| Local Whisper `small` | Local Whisper `small` | Local Whisper audio translate | Passed | `14m 29.824s` | `1.35x` real time | 224 | 15 | 28.86 MB | Success | Fastest Local lane |
| Local Whisper `medium` | Local Whisper `medium` | Local Whisper audio translate | Passed | `34m 16.128s` | `0.57x` real time | 185 | 15 | 28.88 MB | Success | Best Local balance in this pass |
| Local Whisper `large` | Local Whisper `large` | Local Whisper audio translate | Passed | `2h 20m 07.370s` | `0.14x` real time | 355 | 15 | 29.88 MB | Success | Highest-detail Local lane, much slower |
| AI Public | Local Whisper `base` on this PC | OpenAI `gpt-4o-mini-2024-07-18` | Passed | `5m 47.570s` | `3.38x` real time | 225 | 15 | 28.61 MB | Success | Fastest overall, but not directly comparable to pure OpenAI transcription because current AI Public still transcribes locally |
| AI Private | OpenAI `whisper-1` | OpenAI `gpt-5-mini` | Passed | `16m 20.942s` | `1.20x` real time | 251 | 15 | 28.60 MB | Success | Best convenience/quality mix, with one prompt-leak caveat |

## Adaptive timeout planning and calibration

No lane in this pass used an explicit `-WhisperTimeoutSeconds` override. The benchmark intentionally exercised the current adaptive timeout path.

| Lane | Local model used for adaptive plan | Calibration used | Estimated runtime | Resolved adaptive timeout | Stall watchdog | Outcome |
| --- | --- | --- | --- | --- | --- | --- |
| Local `small` transcribe | `small` | No | `27m 56s` | `34m 55s` | `4m 00s` | Completed |
| Local `small` translate | `small` | No | `29m 18s` | `36m 38s` | `4m 00s` | Completed |
| Local `medium` transcribe | `medium` | Yes, `30s` sample in `53s` (`2.08x` RTF) | `46m 31s` | `58m 09s` | `4m 00s` | Completed |
| Local `medium` translate | `medium` | Yes, same calibration pass | `48m 49s` | `1h 01m 01s` | `4m 00s` | Completed |
| Local `large` transcribe | `large` | Yes, `30s` sample in `2m 11s` (`4.40x` RTF) | `1h 38m 06s` | `2h 02m 38s` | `4m 00s` | Completed |
| Local `large` translate | `large` | Yes, same calibration pass | `1h 42m 57s` | `2h 08m 41s` | `4m 00s` | `Completed` |
| AI Public local transcribe | `base` | No | `19m 56s` | `24m 55s` | `4m 00s` | Completed |
| AI Private | n/a | n/a | n/a | n/a | n/a | OpenAI path, no Local Whisper timeout plan |

Notes:

- Local `small` logged that calibration was skipped because the heuristic estimate was not long enough to justify a separate sample.
- Local `medium` and `large` both used the sample-calibration path and completed within the conservative adaptive budgets.
- AI Public currently uses a Local Whisper transcription stage in scripted mode on this branch, so that lane still logged a Local adaptive plan even though translation used OpenAI.
- No lane exceeded its resolved adaptive budget, and no lane needed an explicit benchmark-only timeout override.

## Artifact summary

Each successful lane preserved the normal Audio Mangler package behavior. Every successful lane produced:

- one package folder under its lane root
- `PROCESSING_SUMMARY.csv`
- `CODEX_MASTER_README.txt`
- lane-level console and validator logs
- a package with `README_FOR_CODEX.txt`, `script_run.log`, `segment_index.csv`, `audio/review_audio.mp3`, `transcript/transcript_original.{json,srt,txt}`, and `translations/en/transcript.{json,srt,txt}`

Per-lane artifact counts in this pass:

| Lane | Package files | Total files under lane root | Output bytes |
| --- | ---: | ---: | ---: |
| Local `small` | 10 | 15 | 28,863,838 |
| Local `medium` | 10 | 15 | 28,882,873 |
| Local `large` | 10 | 15 | 29,882,587 |
| AI Public | 10 | 15 | 28,609,568 |
| AI Private | 10 | 15 | 28,596,294 |

## Rough transcript comparison against available source captions

Only the auto-generated `de-orig` caption track was available reliably enough to use as a comparison input. The resulting similarity values should be read as rough relative indicators, not as formal accuracy scores.

| Lane | Detected source language | German word count | English word count | Rough `de-orig` similarity |
| --- | --- | ---: | ---: | ---: |
| Local `small` | `de` | 3193 | 3016 | 0.5334 |
| Local `medium` | `de` | 3156 | 2178 | 0.4805 |
| Local `large` | `de` | 3316 | 3591 | 0.6356 |
| AI Public | `de` | 3146 | 3230 | 0.3644 |
| AI Private | `german` | 3167 | 3371 | 0.6059 |

Practical interpretation:

- `local-large` was the strongest Local match to the available German auto-captions in this pass.
- `ai-private` was close behind on the source-transcript side.
- `ai-public` was clearly weakest against the available German auto-caption reference, which matches the visible transcription mistakes in the output samples.
- `local-medium` appears to compress or summarize more aggressively than the other successful lanes, which likely explains its lower segment count and lower English word count.

## Quality notes

### Observed facts from the outputs

- `Local small` completed quickly and stayed readable for much of the run, but the ending drifted into fragmented English such as `Quatch more with you` and `The video hypes`.
- `Local medium` produced fewer segments (`185`) and a much shorter English transcript (`2178` words) than the other successful lanes, but the resulting translation stayed readable and practically useful.
- `Local large` preserved the most detail among the Local lanes and had the highest rough `de-orig` similarity, but still produced some literal or awkward phrases such as `cool chip` in place of `Crew Chief`.
- `AI Public` produced obvious transcription errors early and late in the run, including `Heuvergag`, `Hayvergag`, `Gucci`, and `Layer-O-Table`.
- `AI Private` was generally smooth and easy to read, but it also leaked translation-prompt text into the output near the end:
  - `Please provide the German transcript segment you want translated (including any sound messages to be noted).`
  - `I don't see the German transcript-please paste the segment you want translated. Also clarify what you mean by "Swery Messages."`
- `AI Private` also carried through the trailing line `Subtitles by the Amara.org community`.

### Practical judgment for operators

- `Local small` is the speed-first Local option, but it is not the best choice when transcript cleanliness matters.
- `Local medium` is the most practical Local default on this CPU-only machine because it stayed readable without turning into a multi-hour wait.
- `Local large` is the best Local quality option here, but it is expensive in wall-clock time for a 20-minute source.
- `AI Public` is the fastest overall lane, but the current scripted path's Local `base` transcription step makes it hard to recommend for quality-sensitive German-to-English work.
- `AI Private` is the easiest high-quality lane overall in this pass, but the prompt-leak and footer cleanup caveats mean it is not a perfect universal winner.

## Errors, blockers, and caveats

- The requested five-lane matrix itself was not blocked. All five lanes passed and validated.
- The benchmark did expose a repeated non-fatal warning in all five lane console logs:
  - `Estimate step failed: The term 'if' is not recognized as the name of a cmdlet...`
- That warning did not stop packaging or validation in this pass, but it should still be treated as a real follow-up defect.
- `yt-dlp` listed an `en` auto-caption track, but download attempts for that track hit `HTTP Error 429: Too Many Requests`, so no reliable source-provided English caption comparison was available.
- Current AI Public scripted behavior still performs Local transcription on this machine, using `base` in this pass, before sending text to OpenAI for translation. That is a comparability caveat, not a benchmark failure.
- Current AI Private output quality is strong overall, but the prompt-leak lines and the extra subtitle footer show that further cleanup/hardening is still warranted.
- Reliable token or cost accounting was not exposed in the current package outputs, so this document does not claim per-lane API cost.

## Final recommendation by scenario

There is no single universal winner from this pass.

- Fastest overall: `AI Public`
- Fastest Local: `Local Whisper small`
- Best Local balance on this CPU-only machine: `Local Whisper medium`
- Best Local quality: `Local Whisper large`
- Best overall convenience: `AI Private`
- Privacy-sensitive recommendation: `Local Whisper medium` first, `Local Whisper large` only when the operator explicitly accepts a multi-hour wait
- Likely best choice for longer CPU-only German-to-English work on this machine: `Local Whisper medium`

Why those recommendations are split:

- Speed and quality did not land on the same lane.
- The highest-detail Local output (`large`) carried a very large runtime penalty.
- The fastest cloud-assisted output (`AI Public`) gave up too much transcript quality in the current scripted configuration.
- The most convenient high-quality lane (`AI Private`) still needs cleanup around prompt leakage and footer carry-through.

## Command record

The exact full commands as actually executed are preserved in each lane's `lane-meta.json` and in `summary/benchmark-metrics.json` under the local evidence root. Repo-relative reproduction commands for the same benchmark matrix are below.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Audio Mangler.ps1" -InputPath "https://www.youtube.com/watch?v=jfySUBLx8Ps&list=PLPEYEQpJkUoCHM84_6N7Bg9bI-boFdr_6" -OutputFolder ".\test-output\benchmark-20260417-german-url-comparison-20260417-203333\local-small" -TranslateTo en -HeartbeatSeconds 10 -NoPrompt -ProcessingMode Local -WhisperModel small
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Audio Mangler.ps1" -InputPath "https://www.youtube.com/watch?v=jfySUBLx8Ps&list=PLPEYEQpJkUoCHM84_6N7Bg9bI-boFdr_6" -OutputFolder ".\test-output\benchmark-20260417-german-url-comparison-20260417-203333\local-medium" -TranslateTo en -HeartbeatSeconds 10 -NoPrompt -ProcessingMode Local -WhisperModel medium
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Audio Mangler.ps1" -InputPath "https://www.youtube.com/watch?v=jfySUBLx8Ps&list=PLPEYEQpJkUoCHM84_6N7Bg9bI-boFdr_6" -OutputFolder ".\test-output\benchmark-20260417-german-url-comparison-20260417-203333\local-large" -TranslateTo en -HeartbeatSeconds 10 -NoPrompt -ProcessingMode Local -WhisperModel large
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Audio Mangler.ps1" -InputPath "https://www.youtube.com/watch?v=jfySUBLx8Ps&list=PLPEYEQpJkUoCHM84_6N7Bg9bI-boFdr_6" -OutputFolder ".\test-output\benchmark-20260417-german-url-comparison-20260417-203333\ai-public" -TranslateTo en -HeartbeatSeconds 10 -NoPrompt -ProcessingMode AI -OpenAiProject Public
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Audio Mangler.ps1" -InputPath "https://www.youtube.com/watch?v=jfySUBLx8Ps&list=PLPEYEQpJkUoCHM84_6N7Bg9bI-boFdr_6" -OutputFolder ".\test-output\benchmark-20260417-german-url-comparison-20260417-203333\ai-private" -TranslateTo en -HeartbeatSeconds 10 -NoPrompt -ProcessingMode AI -OpenAiProject Private
```
