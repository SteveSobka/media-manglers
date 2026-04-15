# Media Manglers

Media Manglers is a small Windows-focused media review toolkit with two standalone apps:

- `Video Mangler` turns videos into review packages with a proxy file, extracted frames, audio, transcripts, optional translated transcripts, and an optional ChatGPT upload zip.
- `Audio Mangler` does the same kind of packaging for audio-first work, with a cleaner transcript-centered flow and optional translated outputs.

The project started as a practical script collection and has grown into a public toolset for people who need to inspect, summarize, translate, and hand off media without juggling five different utilities. Some of the development work was done collaboratively with AI, but the goal here is simple: useful tools that normal people can run.

## Why This Project Exists

Media Manglers started from a real sim-racing workflow problem. High-frame-rate video moves too quickly for ordinary AI review to catch enough detail on its own, so I needed a way to break media into review-friendly artifacts and then point AI at specific moments, frames, and spoken details. That is what led to `Video Mangler`.

`Audio Mangler` grew from the same idea on the audio side: better transcript-first and translation-first workflows built from the original source instead of whatever a platform happened to provide. PowerShell was an intentional choice so the scripts stay easy to inspect and run directly without hiding the logic behind a compiled app, even though packaged executables are available. When the machine can help, the tools use available GPU or CPU acceleration to speed up processing. The optional YouTube comments export came from the same practical need too, because comments are awkward to search in the browser but much easier to review once they are exported to plain text or JSON.

## Which App Is Which?

### Video Mangler

Use `Video Mangler` when the pictures matter as much as the words.

It is built for:

- video review
- interview or talk breakdowns
- extracting stills on a time interval
- turning a remote or local video into something easier to review and share

### Audio Mangler

Use `Audio Mangler` when the spoken content is the main event.

It is built for:

- transcript-first review
- podcasts, interviews, voice notes, lectures, and speeches
- multilingual audio where you want the original transcript plus translated versions
- quicker packaging when you do not need extracted video frames

## Why Someone Would Use This

- You want a clean package instead of a loose pile of files.
- You want to translate from the original spoken source, not from bad platform auto-translation.
- You want to keep a local path available instead of being forced into a paid API.
- You want review-friendly outputs for your own work, a client handoff, or an LLM upload.

## Download

Most people should start with the latest GitHub release:

- [Latest release](https://github.com/SteveSobka/media-manglers/releases/latest)

Release assets usually include:

- `Video-Mangler.exe`
- `Video-Mangler-v0.5.0.zip`
- `Audio-Mangler.exe`
- `Audio-Mangler-v0.5.0.zip`

What to pick:

- `*.exe`: just the app
- `*.zip`: the app plus the plain-text guides, release notes, version file, license, and notices

## Setup Notes

The apps are compiled as Windows executables, but they still rely on a few external tools:

- `FFmpeg` for media processing
- Python plus `openai-whisper` for transcription
- `yt-dlp` for YouTube and other supported remote downloads

Optional translation setup:

- `OPENAI_API_KEY` if you want the OpenAI translation path
- `argostranslate` if you want the free local fallback for non-English translation targets

The apps will explain what is missing. For local translation dependencies, they use a prompt-install flow: they tell you what is missing, what it unlocks, and let you install, skip, or cancel. They do not silently install things.

## Translation Options

Both apps work the same way:

1. Build the original-language transcript from the source audio first.
2. Optionally create translated transcript outputs from that original spoken source.

That matters most for remote video. If you are processing, say, a German YouTube video, Media Manglers is meant to work from the original German speech instead of trusting a weak English auto-track or platform-generated translated captions.

Provider choices:

- `Auto`: use the best available option for each requested language
- `OpenAI`: best quality when configured
- `Local`: free fallback using local tools on your PC

Local behavior:

- English translation can use Whisper locally
- Other targets can use Argos Translate when the needed language packages are installed

OpenAI is optional, not required.

## Privacy And Local Processing

- Local transcription runs on your machine.
- Local translation stays on your machine once the local dependencies are installed.
- OpenAI translation sends transcript text to OpenAI for translation.
- Remote download sources obviously depend on the site you point the app at.

## Example Inputs

Video examples:

- NASA balloon sample: `https://svs.gsfc.nasa.gov/vis/a010000/a014400/a014429/14429_NASA_Balloon_Program_YT.webm`
- Blender open movie on YouTube: `https://www.youtube.com/watch?v=R6MlUcmOul8`

Audio examples:

- LibriVox page: `https://librivox.org/the-gettysburg-address-by-abraham-lincoln-version-2`
- Direct LibriVox MP3: `https://archive.org/download/gettysburg_johng_librivox/gettysburg_address.mp3`
- Multilingual sample MP3: `https://ia801802.us.archive.org/11/items/multilingual028_2103_librivox/msw028_10_maravigliosamente_jacopodalentini_le_128kb.mp3`

## Documentation

- [Overview guide](docs/guides/README.txt)
- [Video Mangler guide](docs/guides/VIDEO_MANGLER.txt)
- [Audio Mangler guide](docs/guides/AUDIO_MANGLER.txt)
- [v0.5.0 release notes](docs/release-notes/RELEASE_NOTES_v0.5.0.txt)

## Testing

Video:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\AREA51\Run-SmokeTest.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\AREA51\Validate-VideoToCodexPackage.ps1
```

Audio:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\AREA51\Run-AudioSmokeTest.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\AREA51\Validate-AudioManglerPackage.ps1
```

## License And Notices

- Repository code: [MIT](LICENSE)
- Third-party notices: [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt)

The MIT license covers the code in this repo. It does not replace the upstream terms for any referenced media, hosted samples, or optional third-party services.
