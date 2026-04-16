# Media Manglers

Media Manglers started as a practical way to break video and audio into pieces that AI can review more accurately.

I originally built it for sim racing. High-frame-rate footage moves fast, and generic AI video review kept missing the details I actually cared about. When I wanted to understand a braking zone, a side-by-side corner entry, or the difference between one lap and another, handing AI one giant video file usually produced broad summaries instead of useful review.

I am not a traditional programmer, and that is part of the story here. I built this collaboratively with AI, using a lot of iteration, testing, re-explaining, and course-correcting until the outputs matched the workflow I needed. What mattered was solving a real problem (collaborating with AI to review video footage).

Instead of treating media like one giant blob, Media Manglers turns it into a review package: proxy media, extracted frames, audio, transcripts, optional translations, comments exports, and optional upload-ready bundles for AI review.

It started as a personal tool, but the workflow turned out to be useful for anyone who needs to inspect, summarize, translate, and hand off media without juggling five different utilities.

That is what this project does: it turns messy, fast-moving media into something you can review on purpose.

## Why This Project Exists

In sim racing, the difference between a strong lap and an average one can be a couple tenths of a second. Those tenths live in details: braking points, turn-in timing, car placement, steering corrections, and what is happening from one moment to the next. Early AI video review was not very good at understanding that kind of footage when I handed it a normal video and asked it to tell me what happened.

So I needed a better way to show AI what mattered.

That led to `Video Mangler`. It breaks video into review-friendly artifacts so analysis can be directed instead of guessed.

The same idea expanded into spoken-content workflows. Sometimes the pictures matter as much as the words. Sometimes the words are the main event. That is where `Audio Mangler` came from: a transcript-first, source-audio-first workflow that stays anchored to the original recording, with optional translated outputs created from the original spoken source.

YouTube comments turned out to be part of the same workflow too. They are often useful context, but reviewing them in the browser is awkward. Exporting them to text or JSON makes them much easier to search, review, and include in an AI workflow.

## A Note On How It Was Built

Most of this project was built collaboratively with AI. That is part of the story as I am a geek, but not a traditional software developer. AI gave me a way to turn a very specific workflow problem into something real. The standard I care about is simple: does the tool solve a real problem, is the logic inspectable, and are the outputs useful? That is the bar I am trying to meet here.

That is also why I chose PowerShell on purpose. The scripts stay easy to inspect and easy to run directly, so the logic is visible instead of hidden behind a compiled black box, even though packaged executables are available.

## What Media Manglers Includes

Media Manglers currently has two standalone apps:

- `Video Mangler` turns video into review packages with a proxy file, extracted frames, audio, transcripts, optional translated transcripts, comments exports, and an optional ChatGPT upload zip.
- `Audio Mangler` does the same kind of packaging for audio-first work, with a cleaner transcript-centered flow and optional translated outputs.

## Which App Is Which?

### Video Mangler

Use `Video Mangler` when the pictures matter as much as the words.

It is built for:

- video review
- sim-racing footage and other fast-moving analysis
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
- You want something inspectable instead of a black box.

## Download

Most people should start with the latest GitHub release:

- [Latest release](https://github.com/SteveSobka/media-manglers/releases/latest)

Release assets usually include:

- `Video-Mangler.exe`
- `Audio-Mangler.exe`
- versioned zip bundles with the app, docs, release notes, version file, license, and notices

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

## How To Create An OpenAI API Key

If you want the OpenAI translation path, create a new secret key in your OpenAI Platform account on the [API Keys page](https://platform.openai.com/api-keys). That is the right place for Media Manglers. You do not need the ChatGPT consumer app for this.

Current OpenAI path in code:

- Media Manglers currently sends translation requests to `POST /v1/chat/completions`.
- It does not use the Responses API for translation today.

Recommended setup for normal local use:

- Use a user-owned OpenAI Platform API key.
- If the Platform lets you scope the key to a project, put Media Manglers in a dedicated project.
- If the key-permission UI clearly shows endpoint permissions, choose `Restricted`.
- On a `Restricted` key, enable `Write` for `Chat Completions` or `/v1/chat/completions` if the UI shows raw endpoint names.
- `Read Only` is not enough because Media Manglers sends `POST /v1/chat/completions` requests for translation.
- You do not need unrelated permissions like Images, Embeddings, Files, Fine-tuning, Vector Stores, Assistants, Batches, or other extras for the current translation path.
- Service accounts are usually for shared automation, servers, CI, or non-personal bot identities, not normal personal desktop use.
- If the permission UI is unclear, the safest fallback is a user-owned key inside a dedicated project with the smallest permission set that still lets Chat Completions work.
- OpenAI API usage may incur charges.

Ways to provide the key on Windows:

- Paste it at the prompt for the current run only.
- Set it for the current PowerShell session:

```powershell
$env:OPENAI_API_KEY="sk-..."
```

- Set it as a persistent Windows user environment variable:

```powershell
[System.Environment]::SetEnvironmentVariable("OPENAI_API_KEY","sk-...","User")
```

After setting the persistent user variable, open a new PowerShell window before rerunning the app.

Do not hardcode the key in either script. Do not commit it to GitHub.

Official OpenAI references:

- [Chat Completions API reference](https://platform.openai.com/docs/api-reference/chat/create-chat-completion)
- [Managing projects in the API platform](https://help.openai.com/en/articles/9186755-managing-your-work-in-the-api-platform-with-projects/)
- [Assign API key permissions](https://help.openai.com/en/articles/8867743-assign-api-key-permissions)

## Translation Options

Both apps work the same way:

1. Build the original-language transcript from the source audio first.
2. Optionally create translated transcript outputs from that original spoken source.

That matters most for remote video. If you are processing, say, a German YouTube video, Media Manglers is meant to work from the original German speech instead of trusting a weak English auto-track or platform-generated translated captions.

For YouTube links, `Video Mangler` now probes the available remote audio-track metadata before the final download when the provider exposes it. If multiple spoken-language tracks are available, interactive runs offer a clean track picker and recommend the original/source spoken audio when it can be identified. `-NoPrompt` runs try to lock onto that original/source track automatically and log a best-effort warning when YouTube metadata does not clearly confirm it.

Provider choices:

- `Auto`: use the best available option for each requested language
- `OpenAI`: best quality when configured with an OpenAI Platform API key
- `Local`: free fallback using local tools on your PC

Local behavior:

- English translation can use Whisper locally
- Other targets can use Argos Translate when the needed language packages are installed

OpenAI is optional, not required.

## Privacy And Local Processing

- Local transcription runs on your machine.
- Local translation stays on your machine once the local dependencies are installed.
- OpenAI translation sends transcript text to the OpenAI API for translation.
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

- Repository code: [Apache License 2.0](LICENSE)
- Third-party notices: [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt)

The Apache License 2.0 covers the code in this repo. It does not replace the upstream terms for any referenced media, hosted samples, or optional third-party services.
