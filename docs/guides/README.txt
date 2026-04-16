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

Both apps now use the same general translation approach:

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

Translation providers:

- Auto: choose the best available option
- OpenAI: usually the best quality when you have an API key configured
- Local: free fallback that runs on your machine

Local translation options:

- English translation can use Whisper locally
- Other target languages can use Argos Translate when its language packages are
  installed

Missing local translation dependencies are handled with a prompt-install flow.
The apps explain what is missing, why it helps, and how to install it. They do
not silently install anything.

Privacy and processing
----------------------

- Local transcription runs on your machine.
- Local translation stays on your machine once the needed tools are installed.
- OpenAI translation sends transcript text to OpenAI.
- Remote downloads depend on the source you point the app at.

Optional comments export
------------------------

For supported YouTube sources, both apps can optionally save public comments
into the output package. This is optional, not automatic, and only included
when the underlying toolchain can retrieve comments reliably for that source.

Useful docs
-----------

- VIDEO_MANGLER.txt
- AUDIO_MANGLER.txt
- ../release-notes/RELEASE_NOTES_v0.5.0.txt

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
- dist\release\Video-Mangler-v0.5.0.zip
- dist\release\Audio-Mangler-v0.5.0.zip

Legacy release clutter is moved under dist\archive\release\ instead of being
left mixed into the live release folder. Temporary packaging folders are also
removed automatically after a successful build.

If you want to inspect the package staging contents for debugging, opt in:

  powershell -NoProfile -ExecutionPolicy Bypass -File .\AREA51\Build-Exe.ps1 -KeepPackageStaging

Smoke tests:

  powershell -NoProfile -ExecutionPolicy Bypass -File .\AREA51\Run-SmokeTest.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File .\AREA51\Run-AudioSmokeTest.ps1

License
-------

- Repository code: Apache License 2.0
- Third-party notices: THIRD_PARTY_NOTICES.txt

The code license applies to the repo itself. Referenced sample media, optional
services, and third-party tools remain under their own terms.
