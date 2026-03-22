# media-manglers

Windows-first PowerShell tooling to turn one or more local video files into a Codex review package.

## Main script

Run the package builder directly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\video_to_codex_package.ps1 `
  -InputPath .\test_media\bbb_sunflower_1080p_60fps_normal.mp4 `
  -OutputFolder .\test-output\manual `
  -FrameIntervalSeconds 0.5 `
  -NoPrompt
```

Notes:

- Default input folder: `C:\TEMP\INPUT`
- Default output folder: `C:\DATA\TEMP`
- `-FrameIntervalSeconds` accepts `0.1` second increments such as `0.3`, `0.5`, `1.0`, `1.1`.
- `-HeartbeatSeconds` controls periodic keep-alive logging during long-running phases. The default is `10`.
- Omit `-NoPrompt` if you want interactive output-folder and frame-interval prompts.
- If you omit `-InputPath` interactively, the script offers `C:\TEMP\INPUT` first and lets you type a different file or folder.
- `-SkipEstimate` disables the best-effort estimate phase.
- GPU acceleration is used when available, with CPU fallback if the GPU path fails.
- Long-running phases emit timestamped `still working...` lines without using fragile PowerShell background event handlers.

## One-shot smoke test

Run the full packaging flow plus artifact validation in one command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-SmokeTest.ps1
```

By default this uses `.\test_media\ToS-4k-1920.mov` as the representative sample from `test_media` when present, creates a fresh timestamped folder under `test-output\`, runs `video_to_codex_package.ps1`, and validates:

- `proxy\review_proxy_1280.mp4`
- `frames_[interval]\frame_*.jpg`
- `audio\audio.mp3`
- `transcript\transcript.srt`
- `transcript\transcript.json`
- `frame_index.csv`
- `README_FOR_CODEX.txt`

Run all supported files in `test_media`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-SmokeTest.ps1 -AllMedia
```

Representative-sample selection behavior:

- Prefer `ToS-4k-1920.mov`, then `bbb_sunflower_1080p_60fps_normal.mp4`, then `2026-03-17_18-59-11.mkv`.
- Otherwise use the largest supported file in `test_media`.

Validated artifacts:

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
  -VideoPath .\test_media\ToS-4k-1920.mov `
  -FrameIntervalSeconds 0.5
```
