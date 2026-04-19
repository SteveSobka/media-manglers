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

Interactive YouTube runs now ask `If comments are available for a YouTube source, save them in the package too? (Y/n):`. Pressing Enter keeps comments on by default. Type `N` or `No` if you want to skip them.

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

- `Video-Mangler-vX.Y.Z.zip`
- `Audio-Mangler-vX.Y.Z.zip`

What to pick:

- `*-vX.Y.Z.zip`: the recommended operator handoff. Each zip includes the app, plain-text guides, release notes, version file, license, notices, and the tracked `python-core` sidecar used by the migration path.
- loose `*.exe`: useful when you build locally and just want a quick executable check. Local build outputs live under `dist\bin\`.

Current migration note:

- The release zips carry `python-core\src\media_manglers` beside the app so the tracked Python helper path has a stable packaged home during the transition.
- `Audio Mangler.ps1` and `Video Mangler.ps1` stay at repo root on purpose because they are the operator-facing source entry points and the inputs to the Windows packaging flow.

## Setup Notes

The apps are compiled as Windows executables, but they still rely on a few external tools:

- `FFmpeg` for media processing
- Python plus `openai-whisper` for local transcription
- `yt-dlp` for YouTube and other supported remote downloads

The main operator choice is now `ProcessingMode`:

- `Local`: local transcription plus local translation
- `AI`: an OpenAI-assisted path that changes slightly depending on `OpenAiProject`
- `Hybrid`: Hybrid Accuracy keeps source audio local, creates the source-language transcript locally first, and uses OpenAI for English text translation only

Mode details:

- `AI Private = OpenAI transcription + OpenAI translation`
- `AI Public = local transcription + OpenAI translation on the Public/shared project`
- `Hybrid = local transcription + OpenAI text-only English translation`

That difference matters. Public AI mode does not behave the same way as Private AI mode, and it does not imply that source audio is always uploaded to OpenAI.

Hybrid Accuracy is currently an initial v1 path. Its first benchmark target is German source media, it supports source-language to English only for now, and broader target-language support is a future follow-up.

- Hybrid now keeps the authoritative source-language transcript in `transcript\` and writes the English text-translation validation report to `translations\en\validation_report.json`.
- Hybrid text translation defaults to `gpt-4o-mini-2024-07-18` when you do not pass `-OpenAiModel`, and the per-run report records both the requested model and the used model.

For Local mode you may also need:

- `argostranslate` for non-English local translation targets
- matching Argos language packages for the source and target languages you request

Interactive Local runs now ask which Whisper model to use. The beginner-friendly default on Enter is `medium`, and the prompt shows `small`, `medium`, and `large` with rough CPU-only transcription-time tradeoffs so operators are not surprised by the Local runtime cost. Scripted or `-NoPrompt` Local runs still keep the current accuracy-first default of `large` unless you explicitly pass `-WhisperModel`.

Interactive translation now asks `Translate the transcript into another language? (Y/n):`. If you answer Yes or just press Enter, the next prompt asks for the target language code and defaults to `en` on Enter.

Local Whisper no longer uses one fixed wall-clock cutoff for every run. Before a Local Whisper run starts, the apps now log the source duration, selected model, whether the Local path looks CPU-only or GPU-capable, the estimated transcription duration, the resolved adaptive timeout, and the separate stall watchdog. Very long interactive Local runs offer a simple continue/switch-smaller/cancel prompt, while `-NoPrompt` runs stay non-interactive. `-WhisperTimeoutSeconds` remains available as an explicit manual override when you need one.

Before a long Local Whisper run, you can now call `-WhisperHealthCheck` in either app to print a short runtime-health summary and exit. That check reports the selected Python interpreter, torch version, torch CUDA version, `cuda_available`, any detected GPU device names, the selected Local Whisper device, and a plain-English classification of the current machine as CPU-only, GPU-capable, or misconfigured/uncertain for Local Whisper. On CPU-only boxes the health check reports CPU-only for Local Whisper; real CUDA sign-off still needs a separate GPU-capable machine.

The apps explain exactly what is missing. For local translation dependencies, they use a prompt-install flow: they tell you what is missing, what it unlocks, and let you install, skip, or cancel. They do not silently install things or silently jump to OpenAI.

## OpenAI Integration

OpenAI is optional. Local mode keeps both transcription and translation on your machine once the local dependencies are installed.

ChatGPT subscriptions and OpenAI API billing are separate. Media Manglers uses the OpenAI API, so AI mode needs API billing/credits on the OpenAI Platform project tied to the key you use.

Current OpenAI paths in code:

- AI model selection can query `GET /v1/models` to see which repo-approved models are visible to the selected key/project
- AI translation uses `POST /v1/chat/completions`
- AI Private transcription uses `POST /v1/audio/transcriptions`

How model selection works in plain English:

- The scripts do not pick from every model a key can see.
- They first check which models are visible to the selected key/project.
- They then choose only from a repo-approved allowlist for the current mode.
- AI Public translation is intentionally pinned to a small approved Public list: `gpt-4o-mini-2024-07-18` first, then `gpt-4.1-mini-2025-04-14`.
- AI Private translation uses a separate approved preference list. Right now it prefers `gpt-5-mini` and only falls back to other approved lower-cost models if that Private key/project cannot use the first choice.
- AI Private transcription keeps the current approved transcription model: `whisper-1`.
- If discovery succeeds, the scripts auto-select the first visible approved model for the chosen mode/project.
- If discovery is skipped or only fails with network / timeout / server-style errors, current main can still fall back to an approved explicit model or an approved default model.
- If discovery fails because of auth, permissions, quota, or because no approved model is visible, the scripts stop instead of silently guessing.
- `-OpenAiModel` is optional. If you set it, it must still be approved for the chosen mode/project. When discovery succeeds, it must also be visible to that key/project.

### Private/Public OpenAI Project Guidance

If you want a Private/Public split, create two separate OpenAI Platform projects:

- one Private project
- one Public/shared project

Important rules:

- Sharing behavior is controlled by the OpenAI project configuration, not by the environment variable name alone.
- Create one API key per project.
- Recommended environment variable names are `OPENAI_API_KEY_PRIVATE` and `OPENAI_API_KEY_PUBLIC`.
- Private is the default and safest AI mode.
- Public only happens when you explicitly run `-ProcessingMode AI -OpenAiProject Public`.
- `OPENAI_API_KEY` is still accepted as a legacy Private fallback for older setups.
- The scripts cannot look at a pasted key and magically tell whether it is Private or Public.
- Use Private for confidential, sensitive, internal, client, or proprietary media.
- Use Public only for media you are allowed to share with OpenAI.
- Public/shared complimentary tokens only apply when the OpenAI project is configured for shared traffic and the request uses an eligible model. They are not unlimited free usage.
- Public mode will not auto-upgrade itself to broader or more expensive models just because the key can see them.
- If a request would cross the remaining complimentary daily quota, OpenAI bills the whole request normally.
- If you are unsure, use Private.

### How To Create An OpenAI API Key

If you want AI mode, create a new secret key in your OpenAI Platform account on the [API Keys page](https://platform.openai.com/api-keys). That is the right place for Media Manglers. You do not need the ChatGPT consumer app for this.

Recommended setup for normal desktop use:

- Create the key in your OpenAI Platform account.
- Choose `Owned by you`.
- Put Media Manglers in a dedicated project.
- Choose `Restricted`.
- Turn on `Request` for `Chat Completions` (`/v1/chat/completions`) because AI translation uses it.
- For AI Private, also turn on `Request` for audio transcription access (`/v1/audio/transcriptions`) because Private AI mode sends source audio to OpenAI for transcription.
- Leave unrelated permissions like Images, Embeddings, Files, Fine-tuning, Vector Stores, Assistants, Batches, and similar extras off or set to `None` unless you actually use them.
- `Read Only` is not enough because Media Manglers sends `POST` requests for transcription and translation.
- Service accounts are mainly for shared automation, servers, CI, or other non-personal bot identities, not normal desktop use.
- OpenAI API usage may incur charges.
- ChatGPT subscriptions and OpenAI API billing are separate.
- If OpenAI returns `429`, check the actual error details. A `429` with `insufficient_quota`, billing, credits, or balance language usually means API billing is not active for that project/account, not that you simply sent requests too quickly.
- If billing or credits are missing, add payment details / credits in the OpenAI API billing settings, wait a few minutes, and retry.

Ways to provide the key on Windows:

- Paste it at the prompt for the current run only.
- Set Private mode for the current PowerShell session:

```powershell
$env:OPENAI_API_KEY_PRIVATE="sk-..."
```

- Set Public mode for the current PowerShell session, then explicitly choose Public:

```powershell
$env:OPENAI_API_KEY_PUBLIC="sk-..."
powershell -NoProfile -ExecutionPolicy Bypass -File '.\Video Mangler.ps1' -TranslateTo en -ProcessingMode AI -OpenAiProject Public
```

- Legacy fallback for older setups:

```powershell
$env:OPENAI_API_KEY="sk-..."
```

- Set a persistent Windows user environment variable:

```powershell
[System.Environment]::SetEnvironmentVariable("OPENAI_API_KEY_PRIVATE","sk-...","User")
```

After setting the persistent user variable, open a new PowerShell window before rerunning the app.

Do not hardcode the key in either script. Do not commit it to GitHub.

### Video Mangler OpenAI Troubleshooting

- `MM_OPENAI_DIAGNOSTICS` is an opt-in troubleshooting setting for `Video Mangler`.
- Set `MM_OPENAI_DIAGNOSTICS=1` to write per-segment diagnostics into an `openai_diagnostics` folder inside the output package.
- You can also set `MM_OPENAI_DIAGNOSTICS` to a folder name or path if you want those files somewhere else.
- Leave it unset during normal runs.
- `Video Mangler` includes a verified Windows PowerShell 5.1 compatibility fix for non-ASCII transcript text on the OpenAI translation path. That failure was request-encoding related, not a separate `frame_index.csv` bug.

Official OpenAI references:

- [Chat Completions API reference](https://platform.openai.com/docs/api-reference/chat/create-chat-completion)
- [Managing projects in the API platform](https://help.openai.com/en/articles/9186755-managing-your-work-in-the-api-platform-with-projects/)
- [Assign API key permissions](https://help.openai.com/en/articles/8867743-assign-api-key-permissions)

## Mode Overview

Both apps now present the same three main choices:

1. `Local mode`
2. `AI mode`
3. `Hybrid Accuracy`

Both apps still build from the source audio first. That matters most for remote video. If you are processing a German YouTube video, Media Manglers is meant to work from the original German speech instead of trusting a weak English auto-track or platform-generated translated captions.

For YouTube links, `Video Mangler` now probes the available remote audio-track metadata before the final download when the provider exposes it. If multiple spoken-language tracks are available, interactive runs offer a clean track picker and recommend the original/source spoken audio when it can be identified. `-NoPrompt` runs try to lock onto that original/source track automatically and log a best-effort warning when YouTube metadata does not clearly confirm it.

Mode behavior in plain English:

- `Local mode`: local transcription plus local translation
- `AI mode` with `Private`: OpenAI transcription plus OpenAI translation
- `AI mode` with `Public`: local transcription plus OpenAI translation on the Public/shared project
- `Hybrid Accuracy`: local source-language transcription first, then OpenAI text-only translation to English while keeping audio local

Local mode does not depend on OpenAI. If Local mode is missing something, the apps explain what local tool or package is missing and stop safely instead of silently switching to OpenAI.

## Privacy And Local Processing

- Local mode keeps transcription and translation on your machine once the local dependencies are installed.
- AI Private sends source audio plus transcript/translation content to OpenAI because it uses OpenAI for both transcription and translation.
- AI Public keeps transcription local and only sends transcript/translation content to the Public/shared OpenAI project.
- Hybrid Accuracy keeps source audio local and sends only transcript text to OpenAI for English translation.
- Remote download sources obviously depend on the site you point the app at.

## Example Inputs

Video examples:

- NASA balloon sample: `https://svs.gsfc.nasa.gov/vis/a010000/a014400/a014429/14429_NASA_Balloon_Program_YT.webm`
- Blender open movie on YouTube: `https://www.youtube.com/watch?v=R6MlUcmOul8`

Audio examples:

- LibriVox page: `https://librivox.org/the-gettysburg-address-by-abraham-lincoln-version-2`
- Direct LibriVox MP3: `https://archive.org/download/gettysburg_johng_librivox/gettysburg_address.mp3`
- Multilingual sample MP3: `https://ia801802.us.archive.org/11/items/multilingual028_2103_librivox/msw028_10_maravigliosamente_jacopodalentini_le_128kb.mp3`

## Command-line summary

### Shared behavior

- `-ProcessingMode` is the main operator-facing control. If you do not pass it, both apps default to `Local`.
- If you do not explicitly pass `-WhisperModel` and the resolved mode is `Local`, interactive runs prompt for `small`, `medium`, or `large` and default to `medium` on Enter. `-NoPrompt` and other scripted Local runs still keep the current `large` default unless you set `-WhisperModel` yourself.
- Hybrid Accuracy defaults `-TranslateTo` to `en` and defaults `-WhisperModel` to `medium` when you do not explicitly override either one.
- Hybrid Accuracy text translation currently defaults to `gpt-4o-mini-2024-07-18` when you do not explicitly pass `-OpenAiModel`.
- `-OpenAiProject Private` means OpenAI transcription plus OpenAI translation in `AI` mode, or private-project OpenAI text translation in `Hybrid` mode. `-OpenAiProject Public` means local transcription plus OpenAI translation on the Public/shared project in `AI` mode, or Public/shared-project OpenAI text translation in `Hybrid` mode.
- `-OpenAiModel` only matters when OpenAI translation is requested in `AI` or `Hybrid`. AI mode keeps the existing repo-side allowlist/discovery path. Hybrid now resolves its text model inside the tracked Python helper, records `requested_model` and `used_model` in `translations\en\validation_report.json`, and surfaces `Model unavailable for selected OpenAI project.` when the chosen project cannot use the requested model.
- `-NoPrompt` disables the interactive questions. Without `-NoPrompt`, the apps prompt for missing inputs and treat Enter as Yes for `CopyRaw*`, `CreateChatGptZip`, `OpenOutputInExplorer`, and supported YouTube comments prompts.
- `-WhisperHealthCheck` runs a Local Whisper runtime probe, prints whether this machine is CPU-only, GPU-capable, or misconfigured/uncertain for Whisper, and exits without starting a packaging run.
- `-Version` and `-ShowVersion` are aliases for the same version-only path.

### Video Mangler

- `-InputPath` / `-InputUrl`: Process a local video file/folder or a direct/page/YouTube URL. If omitted, interactive runs ask and non-interactive runs scan `-InputFolder`.
- `-InputFolder`: Default scan/cache root when `-InputPath` is omitted. Literal default: `C:\DATA\TEMP\_VIDEO_INPUT`. If you did not set it and the `D:` default already exists, current main switches to `D:\DATA\TEMP\_VIDEO_INPUT`.
- `-OutputFolder`: Root folder for output packages and logs. Literal default: `C:\DATA\TEMP\_VIDEO_OUTPUT`. If you did not set it and the `D:` default already exists, current main switches to `D:\DATA\TEMP\_VIDEO_OUTPUT`.
- `-FFmpegPath`: Override the `ffmpeg.exe` path. Literal default: `D:\APPS\ffmpeg\bin\ffmpeg.exe`, with command/path fallback detection.
- `-PythonExe`: Override the Python launcher used for Whisper, Argos, and the `yt-dlp` module fallback. Default: `py`.
- `-YtDlpPath`: Override the `yt-dlp` command/path used for remote inputs. Default: `yt-dlp`.
- `-WhisperModel`: Choose the local Whisper model. Literal script default: `base.en`. Interactive Local runs now prompt for `small`, `medium`, or `large` and default to `medium` on Enter. Non-interactive Local runs still default to `large` when you do not explicitly set the parameter. Hybrid v1 defaults to `medium` unless you override it.
- `-Language`: Optional source-language hint for transcription and local translation. Leave blank to auto-detect when possible.
- `-TranslateTo`: Comma-separated target language codes such as `en` or `en,es`. Blank means no translated transcript outputs in scripted runs. Interactive runs now ask a yes/no question first and default the follow-up target-code prompt to `en`.
- `-ProcessingMode`: Primary mode switch. Valid values: `Local`, `AI`, `Hybrid`. Default: `Local`.
- `-TranslationProvider`: Legacy compatibility flag. Valid values: `Auto`, `OpenAI`, `Local`. Current main maps it into `ProcessingMode`; new runs should prefer `-ProcessingMode`.
- `-OpenAiModel`: Optional OpenAI translation model request. Explicit values must be repo-approved for the chosen mode/project and, when discovery succeeds, visible to that key/project.
- `-OpenAiProject`: Valid values: `Private`, `Public`. Default: `Private` when `AI` or `Hybrid` mode is used. Ignored in Local mode.
- `-FrameIntervalSeconds`: Extract one frame every N seconds. Real default: `0.5`. Interactive runs prompt with `0.5` as the default; `-NoPrompt` runs take `0.5` automatically.
- `-HeartbeatSeconds`: How often long-running steps log progress. Default: `10`.
- `-WhisperTimeoutSeconds`: Optional explicit Local Whisper runtime-budget override in seconds. Leave it unset to use the adaptive timeout logic.
- `-CopyRawVideo`: Copy the original source video into the package `raw` folder. CLI default: off. Interactive default on Enter: Yes.
- `-IncludeComments`: Request YouTube comments when the source supports them. CLI default: off. Interactive YouTube default on Enter: Yes.
- `-CreateChatGptZip`: Build `chatgpt_review_package.zip` for each completed package. CLI default: off. Interactive default on Enter: Yes.
- `-KeepTempFiles`: Keep temporary working files and download caches instead of cleaning them up. Default: off.
- `-OpenOutputInExplorer`: Open the output folder in Windows Explorer when the run finishes. CLI default: off. Interactive default on Enter: Yes.
- `-NoPrompt`: Disable interactive questions and use the non-interactive defaults described above.
- `-SkipEstimate`: Skip the runtime estimate stage. Default: off.
- `-WhisperHealthCheck`: Probe the selected Local Whisper runtime, print the machine classification plus the key runtime facts, and exit.
- `-Version` / `-ShowVersion`: Print the app version and exit.
- `-ChatGptZipMaxMb`: Maximum ChatGPT ZIP size in MB. Default: `500`.

Video Mangler examples:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File '.\Video Mangler.ps1' -Version
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File '.\Video Mangler.ps1' -WhisperHealthCheck
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File '.\Video Mangler.ps1' -InputPath 'C:\Videos\session' -OutputFolder 'C:\Reviews\Video' -TranslateTo en -NoPrompt
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File '.\Video Mangler.ps1' -InputUrl 'https://svs.gsfc.nasa.gov/vis/a010000/a014400/a014429/14429_NASA_Balloon_Program_YT.webm' -TranslateTo en -ProcessingMode AI -OpenAiProject Private -NoPrompt
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File '.\Video Mangler.ps1' -InputUrl 'https://www.youtube.com/watch?v=R6MlUcmOul8' -TranslateTo en -ProcessingMode AI -OpenAiProject Public -OpenAiModel gpt-4.1-mini-2025-04-14 -IncludeComments -NoPrompt
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File '.\Video Mangler.ps1' -InputPath 'C:\Videos\lap.mp4' -FrameIntervalSeconds 1.0 -CreateChatGptZip -NoPrompt
```

### Audio Mangler

- `-InputPath` / `-InputUrl`: Process a local audio file/folder or a direct/page/YouTube URL. If omitted, interactive runs ask and non-interactive runs scan `-InputFolder`.
- `-InputFolder`: Default scan/cache root when `-InputPath` is omitted. Literal default: `C:\DATA\TEMP\_AUDIO_INPUT`. If you did not set it and the `D:` default already exists, current main switches to `D:\DATA\TEMP\_AUDIO_INPUT`.
- `-OutputFolder`: Root folder for output packages and logs. Literal default: `C:\DATA\TEMP\_AUDIO_OUTPUT`. If you did not set it and the `D:` default already exists, current main switches to `D:\DATA\TEMP\_AUDIO_OUTPUT`.
- `-FFmpegPath`: Override the `ffmpeg.exe` path. Literal default: `D:\APPS\ffmpeg\bin\ffmpeg.exe`, with command/path fallback detection.
- `-PythonExe`: Override the Python launcher used for Whisper, Argos, and the `yt-dlp` module fallback. Default: `py`.
- `-YtDlpPath`: Override the `yt-dlp` command/path used for remote inputs that need it. Default: `yt-dlp`.
- `-WhisperModel`: Choose the local Whisper model. Literal script default: `base`. Interactive Local runs now prompt for `small`, `medium`, or `large` and default to `medium` on Enter. Non-interactive Local runs still default to `large` when you do not explicitly set the parameter. Hybrid v1 defaults to `medium` unless you override it.
- `-Language`: Optional source-language hint for transcription and local translation. Leave blank to auto-detect when possible.
- `-TranslateTo`: Comma-separated target language codes such as `en` or `en,es`. Blank means no translated transcript outputs in scripted runs. Interactive runs now ask a yes/no question first and default the follow-up target-code prompt to `en`.
- `-ProcessingMode`: Primary mode switch. Valid values: `Local`, `AI`, `Hybrid`. Default: `Local`.
- `-TranslationProvider`: Legacy compatibility flag. Valid values: `Auto`, `OpenAI`, `Local`. Current main maps it into `ProcessingMode`; new runs should prefer `-ProcessingMode`.
- `-OpenAiModel`: Optional OpenAI translation model request. Explicit values must be repo-approved for the chosen mode/project and, when discovery succeeds, visible to that key/project.
- `-OpenAiProject`: Valid values: `Private`, `Public`. Default: `Private` when `AI` or `Hybrid` mode is used. Ignored in Local mode.
- `-HeartbeatSeconds`: How often long-running steps log progress. Default: `10`.
- `-WhisperTimeoutSeconds`: Optional explicit Local Whisper runtime-budget override in seconds. Leave it unset to use the adaptive timeout logic.
- `-CopyRawAudio`: Copy the original source audio into the package `raw` folder. CLI default: off. Interactive default on Enter: Yes.
- `-IncludeComments`: Request YouTube comments when the source supports them. CLI default: off. Interactive YouTube default on Enter: Yes.
- `-CreateChatGptZip`: Build `chatgpt_review_package.zip` for each completed package. CLI default: off. Interactive default on Enter: Yes.
- `-KeepTempFiles`: Keep temporary working files and download caches instead of cleaning them up. Default: off.
- `-OpenOutputInExplorer`: Open the output folder in Windows Explorer when the run finishes. CLI default: off. Interactive default on Enter: Yes.
- `-NoPrompt`: Disable interactive questions and use the non-interactive defaults described above.
- `-SkipEstimate`: Skip the runtime estimate stage. Default: off.
- `-WhisperHealthCheck`: Probe the selected Local Whisper runtime, print the machine classification plus the key runtime facts, and exit.
- `-Version` / `-ShowVersion`: Print the app version and exit.
- `-ChatGptZipMaxMb`: Maximum ChatGPT ZIP size in MB. Default: `500`.

Audio Mangler examples:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File '.\Audio Mangler.ps1' -Version
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File '.\Audio Mangler.ps1' -WhisperHealthCheck
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File '.\Audio Mangler.ps1' -InputPath 'C:\Audio\interview.mp3' -OutputFolder 'C:\Reviews\Audio' -TranslateTo en,es -NoPrompt
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File '.\Audio Mangler.ps1' -InputUrl 'https://archive.org/download/gettysburg_johng_librivox/gettysburg_address.mp3' -TranslateTo en -ProcessingMode AI -OpenAiProject Private -NoPrompt
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File '.\Audio Mangler.ps1' -InputUrl 'https://www.youtube.com/watch?v=R6MlUcmOul8' -TranslateTo en -ProcessingMode AI -OpenAiProject Public -IncludeComments -NoPrompt
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File '.\Audio Mangler.ps1' -InputPath 'C:\Audio\note.wav' -WhisperModel medium -KeepTempFiles -NoPrompt
```

## Documentation

- [Overview guide](docs/guides/README.txt)
- [Video Mangler guide](docs/guides/VIDEO_MANGLER.txt)
- [Audio Mangler guide](docs/guides/AUDIO_MANGLER.txt)
- [v0.7.0 release notes](docs/release-notes/RELEASE_NOTES_v0.7.0.txt)

## Repo Layout

- `Audio Mangler.ps1` and `Video Mangler.ps1`: operator-facing wrappers and the Windows packaging entry points, kept at repo root on purpose.
- `glossaries/`: tracked runtime glossary assets. Hybrid German-to-English runs use `de-en-sim-racing.json`.
- `tests/`: tracked unit and regression coverage.
- `test-output/`: generated local output from smoke runs, benchmarks, and validation passes. It is intentionally ignored.
- `tools/release/`: tracked release packaging scripts.
- `tools/smoke/`: tracked smoke helpers for bounded local validation.
- `tools/validation/`: tracked package validators and release/source parity checks.
- `AREA51/`: local-only scratch space and optional private fixtures. It is not part of the tracked product surface.

## Testing

The smoke scripts live under `tools\smoke\` and the validators live under `tools\validation\`. When a local fixture exists under `AREA51\TestData`, the smoke helpers prefer that short local file first. If not, they fall back to `test_media`, `test_audio`, or the older remote sample URLs.

Video:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\smoke\Run-SmokeTest.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validation\Validate-VideoToCodexPackage.ps1
```

Audio:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\smoke\Run-AudioSmokeTest.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validation\Validate-AudioManglerPackage.ps1
```

## Benchmark Snapshot

A one-time longer German-to-English benchmark on 2026-04-17 compared Local Whisper `small`, `medium`, and `large` against AI Public and AI Private using the same 19m35s YouTube source through the normal Audio Mangler packaging path. On this CPU-only developer box, `small` was the fastest Local lane, `medium` was the best Local balance, `large` gave the best Local detail but took more than 2 hours, AI Public was fastest overall but weakest on transcript quality in the current scripted path, and AI Private was the best convenience/quality mix with a few cleanup caveats.

The short version for operators is: use `Local medium` for longer privacy-sensitive CPU-only work, use `Local large` only when you explicitly want the best Local quality and can wait, and treat AI lanes as convenience-first options with different quality/privacy tradeoffs. Full methodology, exact timings, caption-comparison limits, and caveats are in [docs/benchmarks/2026-04-17-german-to-english-transcription-benchmark.md](docs/benchmarks/2026-04-17-german-to-english-transcription-benchmark.md).

## License And Notices

- Repository code: [Apache License 2.0](LICENSE)
- Third-party notices: [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt)

The Apache License 2.0 covers the code in this repo. It does not replace the upstream terms for any referenced media, hosted samples, or optional third-party services.
