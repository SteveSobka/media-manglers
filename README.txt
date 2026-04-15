Media Manglers
==============

This repo contains two Windows tools:

- Video Mangler
- Audio Mangler

Use the latest release
----------------------

For most people, use the precompiled Windows downloads from the latest GitHub release:

  https://github.com/SteveSobka/media-manglers/releases/latest

Download choices:

- Video-Mangler.exe
- Video-Mangler-v0.4.0.zip
- Audio-Mangler.exe
- Audio-Mangler-v0.4.0.zip

Use the zip if you want the executable packaged with plain-text docs, release notes, license text, and the VERSION file.

What each tool does
-------------------

Video Mangler

- builds a review package from a local video file, local video folder, remote video URL, or YouTube URL/playlist
- creates a review proxy video, extracted frames, audio, transcript files, a frame index CSV, and an optional ChatGPT upload zip
- app guide: VIDEO_MANGLER.txt

Audio Mangler

- builds a transcript-first review package from a local audio file, local audio folder, direct audio URL, supported web page, or YouTube URL/playlist
- creates review audio, transcript files, translated transcript files when requested, a segment index CSV, and an optional ChatGPT upload zip
- app guide: AUDIO_MANGLER.txt

Public example inputs
---------------------

Video Mangler examples:

- NASA balloon sample:
  https://svs.gsfc.nasa.gov/vis/a010000/a014400/a014429/14429_NASA_Balloon_Program_YT.webm
- Blender open movie on YouTube:
  https://www.youtube.com/watch?v=R6MlUcmOul8

Audio Mangler examples:

- LibriVox page:
  https://librivox.org/the-gettysburg-address-by-abraham-lincoln-version-2
- Direct LibriVox MP3:
  https://archive.org/download/gettysburg_johng_librivox/gettysburg_address.mp3
- Multilingual sample MP3:
  https://ia801802.us.archive.org/11/items/multilingual028_2103_librivox/msw028_10_maravigliosamente_jacopodalentini_le_128kb.mp3

Audio translation
-----------------

Audio Mangler always creates the original-language transcript.

Optional translation behavior:

- Translate to English: handled locally through Whisper
- Translate to other languages: uses OpenAI

To request non-English translation targets, set:

  OPENAI_API_KEY

Example:

  Audio Mangler.exe -TranslateTo en,es

Testing
-------

AREA51 contains the repo's smoke-test and validation scripts.

Video:

- Run smoke test:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\AREA51\Run-SmokeTest.ps1
- Validate latest smoke output:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\AREA51\Validate-VideoToCodexPackage.ps1 -FrameIntervalSeconds 0.5

Audio:

- Run smoke test:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\AREA51\Run-AudioSmokeTest.ps1
- Run translation smoke test:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\AREA51\Run-AudioSmokeTest.ps1 -TranslateToEnglish
- Validate latest audio smoke output:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\AREA51\Validate-AudioManglerPackage.ps1

The default audio smoke test starts with the direct Gettysburg MP3 and automatically falls back to the LibriVox page if the direct file is temporarily unavailable upstream.

Build from source
-----------------

Run either script directly:

  powershell -NoProfile -ExecutionPolicy Bypass -File '.\Video Mangler.ps1'
  powershell -NoProfile -ExecutionPolicy Bypass -File '.\Audio Mangler.ps1'

Show versions:

  powershell -NoProfile -ExecutionPolicy Bypass -File '.\Video Mangler.ps1' -Version
  powershell -NoProfile -ExecutionPolicy Bypass -File '.\Audio Mangler.ps1' -Version

Rebuild both executables:

  powershell -NoProfile -ExecutionPolicy Bypass -File .\AREA51\Build-Exe.ps1

Rebuild only one app:

  powershell -NoProfile -ExecutionPolicy Bypass -File .\AREA51\Build-Exe.ps1 -App Video
  powershell -NoProfile -ExecutionPolicy Bypass -File .\AREA51\Build-Exe.ps1 -App Audio

License
-------

- Repository code: MIT
- Third-party media notices: THIRD_PARTY_NOTICES.txt

The repo code license does not replace the upstream license terms for NASA, Wikimedia Commons, Blender, LibriVox, Internet Archive, YouTube-hosted media, or any other referenced sample media.
