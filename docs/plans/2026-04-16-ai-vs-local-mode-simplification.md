# AI vs Local Mode Simplification

## Current State

- `Video Mangler.ps1` already has a verified Windows PowerShell 5.1 UTF-8 fix for OpenAI translation of non-ASCII transcript segments.
- `Audio Mangler.ps1` still uses the older OpenAI path and still needs the same UTF-8-safe transcript read and UTF-8 request-body behavior carried over.
- Both apps still present the old translation-provider model (`Auto`, `OpenAI`, `Local`) instead of a simpler end-to-end mode choice.
- Both apps currently use local Whisper transcription.
- Public and Private OpenAI project behavior is documented, but the operator-facing mode model is still confusing.
- The repo does not yet have this pass plan file or a `docs/plans/` folder.

## Desired State

- Operator-facing mode model is simplified to:
  - `ProcessingMode Local` = local transcription + local translation
  - `ProcessingMode AI` + `OpenAiProject Private` = OpenAI transcription + OpenAI translation
  - `ProcessingMode AI` + `OpenAiProject Public` = local transcription + OpenAI translation on the Public/shared project
- Legacy provider flags can remain for compatibility, but docs and prompts must center the simpler Local vs AI model.
- Prompt text must match real defaults. If bare Enter means Yes for YouTube comments, the visible prompt must be:
  - `If comments are available for a YouTube source, save them in the package too? (Y/n):`
- README, guides, packaged docs, generated package/operator docs, and TODO state stay in sync.

## Major Risks

- Windows PowerShell 5.1 UTF-8 regressions in live OpenAI translation and transcript handling.
- OpenAI transcription upload-size limits for longer media and the need to preserve package-friendly timestamped transcript output.
- Beginner-facing docs accidentally implying that AI Private and AI Public behave the same way.
- Accidental staging of local-only files, diagnostics, generated artifacts, `test-output`, or `dist` noise.

## Testing Matrix

- A. VIDEO - Local mode - English source
- B. VIDEO - Local mode - foreign-language source
- C. VIDEO - AI mode - English source (`OpenAiProject Private`)
- D. VIDEO - AI mode - foreign-language source (`OpenAiProject Private`)
- E. AUDIO - Local mode - English source
- F. AUDIO - Local mode - foreign-language source
- G. AUDIO - AI mode - English source (`OpenAiProject Private`)
- H. AUDIO - AI mode - foreign-language source (`OpenAiProject Private`)
- Supplement: one `AI Public` video run and one `AI Public` audio run to verify local transcription plus Public/shared-project OpenAI translation.

## Branch / PR Intent

- Branch base: `codex/openai-utf8-fix-and-guidance` at `d3a7157`
- Working branch: `codex/ai-local-mode-simplification`
- PR intent: draft PR to `main` covering the end-to-end Local vs AI simplification, the live Video root-cause verification, Audio UTF-8/OpenAI parity, docs alignment, and matrix validation.

## Repo Hygiene

- If tracked documentation required by this pass is missing, create it and keep it in sync with the rest of the operator docs.
- Local-only recurring files should be ignored or otherwise handled so they do not keep surfacing as repeated status noise for this pass.
- Final commit/PR prep must verify `git status` is clean of accidental local-only files, temporary diagnostics, generated artifacts, `test-output`, and `dist` outputs.
