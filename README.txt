Video Mangler
==============

Build a review package from:

- a local video file
- a local folder of videos
- a remote video URL
- a YouTube video or public playlist

Each package includes:

- a review proxy video
- extracted frames
- audio
- transcript files
- a frame index CSV
- an optional ChatGPT upload zip

Download and run
----------------

For most people, use the Windows executable from the latest release:

1. Download Video Mangler.exe from the latest release.
2. Run it.
3. Follow the prompts.

Current release:

https://github.com/SteveSobka/media-manglers/releases/latest

Check the app version:

  & '.\Video Mangler.exe' -Version

What the app asks
-----------------

When it starts, you choose one input method:

1. Paste YouTube video or playlist URLs
2. Use the default input folder
3. Paste a full local video file path or folder path

Notes:

- Press Enter to default to option 3
- Type Q to quit
- Local paths can be pasted with or without surrounding quotes

Typical local path examples
---------------------------

Single file:

  C:\Videos\clip.mp4

Folder of videos:

  C:\Videos\session-exports

Quoted path:

  "C:\Video Input\raw footage\session_01.mkv"

Typical remote examples
-----------------------

Single public remote video:

  https://download.blender.org/demo/movies/ToS/tears_of_steel_720p.mov

Open-source YouTube video:

  https://www.youtube.com/watch?v=R6MlUcmOul8

Multiple public URLs in one paste:

  https://download.blender.org/demo/movies/ToS/tears_of_steel_720p.mov
  https://download.blender.org/demo/movies/Sintel.2010.720p.mkv

Public YouTube playlist:

  <PUBLIC_YOUTUBE_PLAYLIST_URL>

Output
------

By default the app uses:

- input folder: C:\DATA\TEMP\_VIDEO_INPUT
- output folder: C:\DATA\TEMP\_VIDEO_OUTPUT

If matching D:\DATA\TEMP\... folders already exist instead, it can use those.

Each finished video package contains:

- proxy\review_proxy_1280.mp4
- frames_[interval]\
- audio\audio.mp3
- transcript\transcript.srt
- transcript\transcript.json
- frame_index.csv
- README_FOR_CODEX.txt

Optional:

- chatgpt_review_package.zip

ChatGPT zip behavior
--------------------

If ChatGPT zip creation is enabled:

- the script keeps the core review files
- it includes the proxy if it fits
- if needed, it automatically reduces the zip contents to stay under the size limit
- the full main package stays untouched

YouTube and remote downloads
----------------------------

- Remote downloads require yt-dlp
- On Windows, install it with: winget install yt-dlp.yt-dlp
- The script asks yt-dlp for the best available video/audio and merges to .mp4 when possible
- Some playlist items may still download into mixed containers such as .mp4, .mkv, or .webm
- Public playlists continue past unavailable or private entries if other items download successfully

From source
-----------

Run the PowerShell script directly:

  powershell -NoProfile -ExecutionPolicy Bypass -File '.\Video Mangler.ps1'

Show the script version:

  powershell -NoProfile -ExecutionPolicy Bypass -File '.\Video Mangler.ps1' -Version

Rebuild the Windows executable:

  powershell -NoProfile -ExecutionPolicy Bypass -File .\AREA51\Build-Exe.ps1

The current application version is stored in VERSION.

License
-------

- Repository code: MIT (see LICENSE)
- Blender sample media and any other third-party content: see THIRD_PARTY_NOTICES.txt

This repository's MIT license applies to the script/tooling code. It does not replace the upstream license terms for Blender open-movie media referenced in the docs or test flow.

AREA51
------

AREA51 contains the repo's smoke-test and validation scripts.

Smoke test:

  powershell -NoProfile -ExecutionPolicy Bypass -File .\AREA51\Run-SmokeTest.ps1

If test_media is missing or empty, the smoke test falls back to this public Blender sample:

  https://download.blender.org/demo/movies/ToS/tears_of_steel_720p.mov

Validation only:

  powershell -NoProfile -ExecutionPolicy Bypass -File .\AREA51\Validate-VideoToCodexPackage.ps1 -FrameIntervalSeconds 0.5

By default the validator uses the latest smoke-* folder under .\test-output.
If that smoke output contains exactly one package folder, the validator will pick it automatically.
