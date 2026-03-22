# media-manglers

Windows-first PowerShell tooling to turn one or more local video files into a Codex review package.

## Main script

Run the package builder directly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\video_to_codex_package.ps1 `
  -InputPath .\2026-03-17_18-59-11.mkv `
  -OutputFolder .\test-output\manual `
  -FrameIntervalSeconds 0.5 `
  -NoPrompt
```

Notes:

- `-FrameIntervalSeconds` accepts `0.1` second increments such as `0.3`, `0.5`, `1.0`, `1.1`.
- Omit `-NoPrompt` if you want interactive output-folder and frame-interval prompts.
- `-SkipEstimate` disables the best-effort estimate phase.
- GPU acceleration is used when available, with CPU fallback if the GPU path fails.

## One-shot smoke test

Run the full packaging flow plus artifact validation in one command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-SmokeTest.ps1
```

That creates a fresh timestamped folder under `test-output\`, runs `video_to_codex_package.ps1`, and validates:

- `proxy\review_proxy_1280.mp4`
- `frames_[interval]\frame_*.jpg`
- `audio\audio.mp3`
- `transcript\transcript.srt`
- `transcript\transcript.json`
- `frame_index.csv`
- `README_FOR_CODEX.txt`

## Validation only

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-VideoToCodexPackage.ps1 `
  -OutputRoot .\test-output\smoke-YYYYMMDD-HHMMSS `
  -VideoPath .\2026-03-17_18-59-11.mkv `
  -FrameIntervalSeconds 0.5
```
