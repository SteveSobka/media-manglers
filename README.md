# media-manglers

Windows-first PowerShell tooling to turn one or more local or remote video sources into a Codex review package.

## Main script

Run the package builder directly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\video_to_codex_package.ps1 `
  -InputPath .\test_media\bbb_sunflower_1080p_60fps_normal.mp4 `
  -OutputFolder .\test-output\manual `
  -FrameIntervalSeconds 0.5 `
  -NoPrompt
```

Use the dedicated remote-input alias for a single YouTube video:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\video_to_codex_package.ps1 `
  -InputUrl "https://www.youtube.com/watch?v=VIDEO_ID" `
  -OutputFolder .\test-output\youtube `
  -FrameIntervalSeconds 0.5 `
  -NoPrompt
```

Process every video in a YouTube playlist:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\video_to_codex_package.ps1 `
  -InputUrl "https://www.youtube.com/playlist?list=PL5QT34daNj2BPI0Rsjdg3WpJXgK8_UPrP" `
  -OutputFolder .\test-output\playlist `
  -FrameIntervalSeconds 0.5 `
  -NoPrompt
```

Notes:

- Default input folder: `C:\DATA\TEMP\_VIDEO_INPUT`
- Default output folder: `C:\DATA\TEMP\_VIDEO_OUTPUT`
- Auto-detect behavior for defaults when not explicitly passed:
  - If the `C:\DATA\TEMP\...` default folders already exist, the script uses them.
  - Otherwise, if matching `D:\DATA\TEMP\...` folders exist, it uses those.
  - If neither exists, interactive mode asks once for a simple base location.
- `-InputPath` accepts a local video file, a folder of videos, or an `http/https` video URL.
- `-InputUrl` is a dedicated alias for remote video or playlist URLs and is the clearer option when you are downloading first.
- `-FrameIntervalSeconds` accepts `0.1` second increments such as `0.3`, `0.5`, `1.0`, `1.1`.
- `-HeartbeatSeconds` controls periodic keep-alive logging during long-running phases. The default is `10`.
- Omit `-NoPrompt` if you want interactive output-folder and frame-interval prompts.
- If you run the script interactively without `-InputPath` or `-InputUrl`, it asks whether you want to download from YouTube or another supported video URL first.
- In interactive mode, you can paste either a single-video URL or a playlist URL. Playlist URLs download every video before packaging.
- Downloaded remote videos are stored under the selected input folder.
- `-SkipEstimate` disables the best-effort estimate phase.
- Interactive mode now also asks:
  - whether to create a ChatGPT-ready zip package per video
  - whether to open Windows Explorer to the output folder when processing finishes
- GPU acceleration is used when available, with CPU fallback if the GPU path fails.
- Remote URL downloads require `yt-dlp`. On Windows, install it with `winget install yt-dlp.yt-dlp` or `py -m pip install -U yt-dlp`.
- If you choose a remote URL interactively and `yt-dlp` is missing, the script tells you how to install it before continuing.
- Use remote download only for video sources you have permission to download.
- Long-running phases emit timestamped `still working...` lines without using fragile PowerShell background event handlers.

## ChatGPT zip package (optional)

When enabled (`-CreateChatGptZip` or interactive prompt), each processed video gets a `chatgpt_review_package.zip` inside its package folder.

The zip contains:
- `audio\`
- `frames_[interval]\`
- `transcript\`
- `frame_index.csv`
- `README_FOR_CHATGPT.txt`
- `proxy\review_proxy_1280.mp4` only when it fits the configured size limit

Size management:
- Use `-ChatGptZipMaxMb` (default `500`) to cap zip size.
- Proxy video is automatically omitted when needed to stay within the limit.

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
