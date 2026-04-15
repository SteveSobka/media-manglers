# Media Manglers

Two Windows tools live here:

- `Video Mangler`: turns videos into review packages with a proxy, frames, audio, transcript files, and an optional ChatGPT zip
- `Audio Mangler`: turns audio into transcript-first review packages with optional translation and an optional ChatGPT zip

## Download

Most people should use the latest release:

- [Latest release](https://github.com/SteveSobka/media-manglers/releases/latest)

Release assets:

- `Video-Mangler.exe`
- `Video-Mangler-v0.4.0.zip`
- `Audio-Mangler.exe`
- `Audio-Mangler-v0.4.0.zip`

Use the zip if you want the executable bundled with plain-text docs, release notes, license text, and the `VERSION` file.

## App Guides

- [VIDEO_MANGLER.txt](VIDEO_MANGLER.txt)
- [AUDIO_MANGLER.txt](AUDIO_MANGLER.txt)
- [README.txt](README.txt)

## Public Examples

Video examples:

- NASA balloon sample: `https://svs.gsfc.nasa.gov/vis/a010000/a014400/a014429/14429_NASA_Balloon_Program_YT.webm`
- Blender open movie on YouTube: `https://www.youtube.com/watch?v=R6MlUcmOul8`

Audio examples:

- LibriVox page: `https://librivox.org/the-gettysburg-address-by-abraham-lincoln-version-2`
- Direct LibriVox MP3: `https://archive.org/download/gettysburg_johng_librivox/gettysburg_address.mp3`
- Multilingual sample MP3: `https://ia801802.us.archive.org/11/items/multilingual028_2103_librivox/msw028_10_maravigliosamente_jacopodalentini_le_128kb.mp3`

## Audio Translation

`Audio Mangler` always creates the original-language transcript.

Optional translation:

- `en`: Whisper translation
- other languages: OpenAI translation

Non-English translation targets require `OPENAI_API_KEY`.

## AREA51

Video:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\AREA51\Run-SmokeTest.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\AREA51\Validate-VideoToCodexPackage.ps1 -FrameIntervalSeconds 0.5
```

Audio:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\AREA51\Run-AudioSmokeTest.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\AREA51\Run-AudioSmokeTest.ps1 -TranslateToEnglish
powershell -NoProfile -ExecutionPolicy Bypass -File .\AREA51\Validate-AudioManglerPackage.ps1
```

The default audio smoke test starts with the direct Gettysburg MP3 and automatically falls back to the LibriVox page if the direct file is temporarily unavailable upstream.

## Build From Source

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File '.\Video Mangler.ps1'
powershell -NoProfile -ExecutionPolicy Bypass -File '.\Audio Mangler.ps1'
```

Show versions:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File '.\Video Mangler.ps1' -Version
powershell -NoProfile -ExecutionPolicy Bypass -File '.\Audio Mangler.ps1' -Version
```

Build executables:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\AREA51\Build-Exe.ps1
```

## License

- Repository code: [MIT](LICENSE)
- Third-party media notices: [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt)

The repo code license does not replace the upstream terms for referenced NASA, Wikimedia Commons, Blender, LibriVox, Internet Archive, YouTube-hosted, or other sample media.
