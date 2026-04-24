# Issue #31: Hybrid Private `gpt-5-mini` Temperature Omission

## Summary

This approved execute pass stays narrow and Hybrid-only.

- Omit the top-level `temperature` field for Hybrid chat-completions requests using `gpt-5-mini` or `gpt-5-mini-2025-08-07`.
- Keep the existing JSON-prompt-only behavior for those same model IDs: no `response_format`.
- Keep current request behavior unchanged for working Hybrid models such as `gpt-4o-mini-2024-07-18` and `gpt-4.1-mini-2025-04-14`.
- Do not change model resolution, approved-model lists, lane manifests, support policy, provider validation, media, benchmarks, release docs, or `VERSION`.

## Why This Pass

The latest no-media differential evidence isolated the top-level `temperature = 0` field as the likely remaining request-shape trigger for the Private `gpt-5-mini` family. For both explicit model IDs, no-temperature AI-style and Hybrid structured requests succeeded, while adding `temperature = 0` failed with `model_unavailable` / HTTP `400`.

The smallest repo-side follow-up is therefore a code/test-only transport gate, followed by a separate no-media provider validation pass.

## Acceptance

- Hybrid requests using `gpt-5-mini` omit both `response_format` and `temperature`.
- Hybrid requests using `gpt-5-mini-2025-08-07` omit both `response_format` and `temperature`.
- Hybrid requests using `gpt-4o-mini-2024-07-18` and `gpt-4.1-mini-2025-04-14` still include `temperature = 0` and `response_format = {"type": "json_object"}`.
- Existing Hybrid model-selection behavior is unchanged.
- `python -m unittest tests.test_hybrid_text -v` passes.
- Issue `#31` remains open pending separate no-media provider validation.
