Media Manglers
==============

What this project is
--------------------

Media Manglers is a small Windows project with two standalone apps:

- Video Mangler
- Audio Mangler

They are built for people who need a clean review package from media without
assembling the workflow by hand every time.

Video Mangler is for video-first review. It creates a review proxy, extracted
frames, audio, transcripts, optional translated transcripts, and an optional
ChatGPT upload zip.

Audio Mangler is for transcript-first audio review. It creates cleaned review
audio, original-language transcripts, optional translated transcripts, and an
optional ChatGPT upload zip.

The project was developed collaboratively with AI in places, but the point of
the repo is practical media review, not AI experimentation.

How the two apps differ
-----------------------

Choose Video Mangler when visuals matter:

- interviews, talks, presentations, training videos
- source review for clips or edits
- anything where still frames and timeline context help

Choose Audio Mangler when the spoken content is the main thing:

- podcasts
- lectures
- voice notes
- speeches
- multilingual audio review

Quick download path
-------------------

Most people should use the latest GitHub release:

  https://github.com/SteveSobka/media-manglers/releases/latest

You will usually see both of these for each app:

- *.exe
- *.zip

What they mean:

- .exe: just the app
- .zip: the app plus guides, release notes, version text, license text, and
  notices

Translation in plain English
----------------------------

Both apps now use the same two main operator choices:

- Local mode
- AI mode

Both apps still follow the same general media flow:

1. Create the original-language transcript from the source audio first.
2. If you ask for translation, build translated transcript files from that
   original spoken source.

That matters most for remote video and YouTube links. If a platform offers weak
auto-translated audio or captions, Media Manglers is designed to prefer the
original spoken source instead.

For YouTube links, Video Mangler also probes remote audio-track metadata before
the final download when that metadata is exposed. If multiple spoken-language
tracks are available, interactive runs show a track picker and recommend the
original/source audio when it can be identified. NoPrompt runs try to choose
that original/source track automatically and log best-effort wording when the
provider does not confirm it clearly.

Mode behavior:

- Local mode: local transcription plus local translation
- AI Private: OpenAI transcription plus OpenAI translation
- AI Public: local transcription plus OpenAI translation on the Public/shared
  project

Interactive Local runs now ask which Whisper model to use. The beginner-friendly
default on Enter is medium, and the prompt shows small, medium, and large with
rough CPU-only transcription-time tradeoffs so operators are not surprised by
the Local runtime cost. Scripted or -NoPrompt Local runs still keep the current
accuracy-first default of large unless you explicitly pass -WhisperModel.

Interactive translation now asks:

  Translate the transcript into another language? (Y/n):

If you answer Yes or just press Enter, the next prompt asks for the target
language code and defaults to en on Enter.

Local Whisper no longer uses one fixed wall-clock timeout for every run. Before
a Local Whisper run starts, the apps now log the source duration, selected
model, whether the Local path looks CPU-only or GPU-capable, the estimated
transcription duration, the resolved adaptive timeout, and the separate stall
watchdog. Very long interactive Local runs offer a simple continue/switch-
smaller/cancel prompt, while -NoPrompt runs stay non-interactive. You can still
force a manual runtime budget with -WhisperTimeoutSeconds when needed.

Local mode does not depend on OpenAI. If local translation support is missing,
the apps explain what is missing, why it helps, and how to install it. They do
not silently install anything or silently switch to OpenAI.

OpenAI API key setup
--------------------

If you want AI mode, create a new secret key in your OpenAI Platform account on
the API Keys page:

  https://platform.openai.com/api-keys

Current OpenAI paths in code:

- AI model selection can query GET /v1/models to see which repo-approved
  models are visible to the selected key/project.
- AI translation uses POST /v1/chat/completions
- AI Private transcription uses POST /v1/audio/transcriptions

How model selection works:

- The scripts do not pick from every model a key can see.
- They first check which models are visible to the selected key/project.
- They then choose only from a repo-approved allowlist for the current mode.
- AI Public translation is intentionally pinned to a small approved Public
  list: gpt-4o-mini-2024-07-18 first, then gpt-4.1-mini-2025-04-14.
- AI Private translation uses a separate approved preference list. Right now
  it prefers gpt-5-mini and only falls back to other approved lower-cost
  models if that Private key/project cannot use the first choice.
- AI Private transcription keeps the current approved transcription model:
  whisper-1.
- If discovery succeeds, the scripts auto-select the first visible approved
  model for the chosen mode/project.
- If discovery is skipped or only fails with network / timeout / server-style
  errors, current main can still fall back to an approved explicit model or an
  approved default model.
- If discovery fails because of auth, permissions, quota, or because no
  approved model is visible, the scripts stop instead of silently guessing.
- -OpenAiModel is optional. If you set it, it must still be approved for the
  chosen mode/project. When discovery succeeds, it must also be visible to
  that key/project.

Recommended setup for normal local use:

- Create the key in your OpenAI Platform account.
- Choose Owned by you.
- Put Media Manglers in a dedicated project.
- Choose Restricted.
- In the current OpenAI Platform UI, turn on Request for Chat Completions
  (/v1/chat/completions).
- For AI Private, also turn on Request permission for audio transcription
  access because Private AI mode sends source audio to OpenAI for
  transcription.
- Leave unrelated permissions like Images, Embeddings, Files, Fine-tuning,
  Vector Stores, Assistants, Batches, and similar extras off or set to None
  unless you actually use them.
- Read Only is not enough because Media Manglers sends POST requests for
  transcription and translation.
- Service accounts are mainly for shared automation, servers, CI, or other
  non-personal bot identities, not normal desktop use.
- OpenAI API usage may incur charges.
- Private is the default and safest AI mode.
- Public mode only happens when you explicitly choose AI mode with
  -OpenAiProject Public.
- Use OPENAI_API_KEY_PRIVATE for the default Private path.
- Use OPENAI_API_KEY_PUBLIC only when you explicitly choose the Public/shared
  project.
- OPENAI_API_KEY still works as a legacy Private fallback for older setups.
- Public/shared complimentary tokens only apply when the Public project is
  configured for shared traffic and the request uses an eligible model.
- Public mode will not auto-upgrade itself to broader or more expensive models
  just because the key can see them.
- If a request would cross the remaining complimentary daily quota, OpenAI
  bills the whole request normally.
- Use Private for confidential or sensitive media. Use Public only for media
  you are allowed to share with OpenAI.

Ways to provide the key on Windows:

- Paste it at the prompt for the current run only.
- Set Private mode for the current PowerShell session:

  $env:OPENAI_API_KEY_PRIVATE="sk-..."

- Set Public mode for the current PowerShell session, then explicitly choose
  Public:

  $env:OPENAI_API_KEY_PUBLIC="sk-..."
  powershell -NoProfile -ExecutionPolicy Bypass -File '.\Video Mangler.ps1' -TranslateTo en -ProcessingMode AI -OpenAiProject Public

- Legacy fallback for older setups:

  $env:OPENAI_API_KEY="sk-..."

- Set it as a persistent Windows user environment variable:

  [System.Environment]::SetEnvironmentVariable("OPENAI_API_KEY_PRIVATE","sk-...","User")

After setting the persistent user variable, open a new PowerShell window before
rerunning the app.

Do not hardcode the key in the script. Do not commit it to GitHub.

Official OpenAI references:

- https://platform.openai.com/docs/api-reference/chat/create-chat-completion
- https://help.openai.com/en/articles/9186755-managing-your-work-in-the-api-platform-with-projects/
- https://help.openai.com/en/articles/8867743-assign-api-key-permissions

Privacy and processing
----------------------

- Local mode keeps transcription and translation on your machine once the
  needed tools are installed.
- AI Private sends source audio plus transcript/translation content to OpenAI.
- AI Public keeps transcription local and only sends transcript/translation
  content to the Public/shared OpenAI project.
- Remote downloads depend on the source you point the app at.

Optional comments export
------------------------

For supported YouTube sources, both apps can optionally save public comments
into the output package. This is optional, not automatic, and only included
when the underlying toolchain can retrieve comments reliably for that source.

Command-line summary
--------------------

Current main behavior:

- ProcessingMode is the primary operator-facing switch.
- If you do not pass -ProcessingMode, both apps default to Local.
- If you do not explicitly pass -WhisperModel and the resolved mode is Local,
  interactive runs prompt for small, medium, or large and default to medium on
  Enter. -NoPrompt and other scripted Local runs still keep the current large
  default unless you set -WhisperModel yourself.
- -OpenAiProject Private = OpenAI transcription + OpenAI translation.
- -OpenAiProject Public = local transcription + OpenAI translation on the
  Public/shared project.
- -OpenAiModel only matters when AI translation is requested. Current main
  queries GET /v1/models, keeps only the repo-approved allowlist, auto-selects
  the first visible approved model, and only uses an approved fallback when
  discovery is skipped or only hits network / timeout / server-style failures.
- -NoPrompt disables the interactive questions and uses the non-interactive
  defaults.
- -Version and -ShowVersion are aliases for the same version-only path.

See the full per-app command-line summary sections in:

- VIDEO_MANGLER.txt
- AUDIO_MANGLER.txt

Useful docs
-----------

- VIDEO_MANGLER.txt
- AUDIO_MANGLER.txt
- ../release-notes/RELEASE_NOTES_v0.6.1.txt

Build and test
--------------

Run either script directly:

  powershell -NoProfile -ExecutionPolicy Bypass -File '.\Video Mangler.ps1'
  powershell -NoProfile -ExecutionPolicy Bypass -File '.\Audio Mangler.ps1'

Show versions:

  powershell -NoProfile -ExecutionPolicy Bypass -File '.\Video Mangler.ps1' -Version
  powershell -NoProfile -ExecutionPolicy Bypass -File '.\Audio Mangler.ps1' -Version

Rebuild the packaged executables:

  powershell -NoProfile -ExecutionPolicy Bypass -File .\AREA51\Build-Exe.ps1

The build keeps the live output layout minimal by default:

- dist\Video Mangler.exe
- dist\Audio Mangler.exe
- dist\release\Video-Mangler.exe
- dist\release\Audio-Mangler.exe
- dist\release\Video-Mangler-v0.6.1.zip
- dist\release\Audio-Mangler-v0.6.1.zip

During the Python-core migration, the release zips now carry a shared
python-core sidecar inside the app folder. That gives the tracked Python
helper path a stable packaged home without forcing the standalone exe assets to
depend on it yet. If the sidecar is not present, the wrappers still keep the
current compatibility fallback.

Legacy release clutter is moved under dist\archive\release\ instead of being
left mixed into the live release folder. Temporary packaging folders are also
removed automatically after a successful build.

If you want to inspect the package staging contents for debugging, opt in:

  powershell -NoProfile -ExecutionPolicy Bypass -File .\AREA51\Build-Exe.ps1 -KeepPackageStaging

Smoke tests:

  powershell -NoProfile -ExecutionPolicy Bypass -File .\AREA51\Run-SmokeTest.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File .\AREA51\Run-AudioSmokeTest.ps1

The smoke scripts now prefer short local fixtures under AREA51\TestData before
they fall back to test_media, test_audio, or the older remote sample URLs. The
standard fast path is the local 1_min_test_Video.mp4, and audio
translation-to-English smoke coverage also prefers a short local
foreign-language clip when one is present.

License
-------

- Repository code: Apache License 2.0
- Third-party notices: THIRD_PARTY_NOTICES.txt

The code license applies to the repo itself. Referenced sample media, optional
services, and third-party tools remain under their own terms.
