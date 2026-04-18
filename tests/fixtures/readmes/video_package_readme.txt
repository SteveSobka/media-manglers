README_FOR_CODEX

This folder contains a Video Mangler review package for:
1_min_test_Video.mp4

What is included:
- raw\                            original source video (only if you chose to keep a copy)
- proxy\review_proxy_1280.mp4     review copy for playback
- frames_0p5s\frame_000001.jpg ...
- audio\audio.mp3                 only when the source has spoken audio
- transcript\transcript.srt / .json / .txt
- translations\<lang>\transcript.srt / .json / .txt when translation was requested
- comments\comments.txt / .json   public comments export when available and requested
- frame_index.csv                 timestamp index for the extracted frames
- script_run.log                  processing log, including raw OpenAI error details when available

A good review order:
1. Start with transcript\transcript.txt when audio is present.
2. Watch proxy\review_proxy_1280.mp4 for pacing, sequence, and spoken context.
3. Use frame_index.csv to map timestamps to the extracted frames.
4. Check translations\<lang>\ if you asked for translated text.
5. Check comments\ if public source comments were included for context.
6. Use raw video only if the derived review assets are not enough.

Notes:
- Package status: success
- Selected frame interval: 0.5 seconds
- Frames folder: frames_0p5s
- Raw video present: No
- Audio present in source: Yes
- Processing mode used: Local
- AI project mode: not applicable (Local mode)
- Transcription path used: Local (Whisper transcription)
- Detected source language: en
- Remote audio track selected: not applicable (local source or provider metadata unavailable)
- Translation targets: none
- Translation status: not requested
- Translation path used: none
- Translation notes: none
- Next steps: none
- Comments: not included
