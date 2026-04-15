# media-manglers

PowerShell scripts for turning local videos, YouTube videos, or playlists into a review package with:

- a review proxy
- extracted frames
- audio
- transcript files
- frame index CSV
- optional ChatGPT upload zip

## Main script

Run the package builder directly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\video_to_codex_package.ps1 `
  -InputPath .\test_media\bbb_sunflower_1080p_60fps_normal.mp4 `
  -OutputFolder .\test-output\manual `
  -FrameIntervalSeconds 0.5 `
  -NoPrompt
```

Use the dedicated remote-input alias for a single public remote video URL:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\video_to_codex_package.ps1 `
  -InputUrl "https://download.blender.org/demo/movies/ToS/tears_of_steel_720p.mov" `
  -OutputFolder .\test-output\remote-single `
  -FrameIntervalSeconds 0.5 `
  -NoPrompt
```

Process a public YouTube playlist:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\video_to_codex_package.ps1 `
  -InputUrl "<PUBLIC_YOUTUBE_PLAYLIST_URL>" `
  -OutputFolder .\test-output\playlist `
  -FrameIntervalSeconds 0.5 `
  -NoPrompt
```

For multiple public remote videos in one interactive run, use the pasted-URL walkthrough below with the official Blender-hosted movie files.

## Interactive walkthroughs

Single public remote video URL:

```text
PS D:\repo> powershell -NoProfile -ExecutionPolicy Bypass -File .\video_to_codex_package.ps1

Default local input source:
D:\DATA\TEMP\_VIDEO_INPUT
Choose an input method:
  1. Paste YouTube video or playlist URLs
  2. Use this folder: D:\DATA\TEMP\_VIDEO_INPUT
  3. Paste a full local video file path or folder path
Press Enter for 3, or type Q to quit.
Enter 1, 2, 3, or Q: 1
Paste text containing one or more video or playlist URLs.
Type DONE on its own line when the paste is complete.
Paste line 1: https://download.blender.org/demo/movies/ToS/tears_of_steel_720p.mov
Next line: DONE
```

Pasted notes plus multiple public URLs:

```text
Default local input source:
D:\DATA\TEMP\_VIDEO_INPUT
Choose an input method:
  1. Paste YouTube video or playlist URLs
  2. Use this folder: D:\DATA\TEMP\_VIDEO_INPUT
  3. Paste a full local video file path or folder path
Press Enter for 3, or type Q to quit.
Enter 1, 2, 3, or Q: 1
Paste text containing one or more video or playlist URLs.
Type DONE on its own line when the paste is complete.
Paste line 1: Blender open movie files to capture:
Next line:
Next line: Tears of Steel 720p:
Next line: https://download.blender.org/demo/movies/ToS/tears_of_steel_720p.mov
Next line:
Next line: Sintel 720p:
Next line: https://download.blender.org/demo/movies/Sintel.2010.720p.mkv
Next line: DONE
```

Local file walkthrough:

```text
Default local input source:
D:\DATA\TEMP\_VIDEO_INPUT
Choose an input method:
  1. Paste YouTube video or playlist URLs
  2. Use this folder: D:\DATA\TEMP\_VIDEO_INPUT
  3. Paste a full local video file path or folder path
Press Enter for 3, or type Q to quit.
Enter 1, 2, 3, or Q:
Paste a full local video file path or folder path: D:\capture\clip.mp4
```

Local folder walkthrough:

```text
Default local input source:
D:\DATA\TEMP\_VIDEO_INPUT
Choose an input method:
  1. Paste YouTube video or playlist URLs
  2. Use this folder: D:\DATA\TEMP\_VIDEO_INPUT
  3. Paste a full local video file path or folder path
Press Enter for 3, or type Q to quit.
Enter 1, 2, 3, or Q:
Paste a full local video file path or folder path: D:\capture\session-clips
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
- The remote examples in this README use official Blender-hosted open movie files so they stay public and reusable.
- `-FrameIntervalSeconds` accepts `0.1` second increments such as `0.3`, `0.5`, `1.0`, `1.1`.
- `-HeartbeatSeconds` controls periodic keep-alive logging during long-running phases. The default is `10`.
- Omit `-NoPrompt` if you want interactive output-folder and frame-interval prompts.
- If you run the script interactively without `-InputPath` or `-InputUrl`, it asks whether you want to download from YouTube or another supported video URL first.
- In interactive mode, you can paste either a single-video URL, multiple video URLs, or a playlist URL.
- When adding multiple remote URLs interactively, you can paste a whole block of notes plus URLs and the script extracts every `http/https` URL it finds in that pasted text.
- Finish the pasted block by typing `DONE` on its own line.
- Playlist URLs download every available video before packaging.
- Public playlist downloads continue past unavailable, hidden, or private entries when other playlist items are downloadable.
- For playlist runs, replace `<PUBLIC_YOUTUBE_PLAYLIST_URL>` with a public playlist URL you have permission to download.
- Downloaded remote videos are stored under the selected input folder.
- In local-path mode, pasted file and folder paths may be wrapped in single or double quotes.
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
- If the package is still too large, the script automatically thins the frame set for the ChatGPT zip only until the archive fits.
- The full package in the main output folder is left untouched; only the ChatGPT upload zip is reduced when necessary.
- `README_FOR_CHATGPT.txt` notes whether all frames were included or whether the frame set was automatically sampled to fit the limit.

## Remote download format notes

- The script does not force YouTube downloads to `.webm`.
- The script explicitly asks `yt-dlp` for the best available video+audio combination and uses FFmpeg to merge to `.mp4` when possible.
- When a playlist contains videos with different source formats or different remux/merge possibilities, the downloaded raw files may still end up with mixed containers across the playlist.
- If a clean MP4 merge is not possible for the source, the raw download may still end up in another supported container such as `.webm`.
- The raw copied source video preserves whatever container `yt-dlp` downloaded.
- If `yt-dlp` is installed but not yet visible on `PATH` in the current shell, you can still run the script by passing `-YtDlpPath` with the full executable path.

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
