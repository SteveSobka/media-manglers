# Issue #31: Hybrid Private `gpt-5-mini` Request-Shape Follow-up

## Summary

This approved execute pass stays narrow and Hybrid-only.

- Update `src/media_manglers/providers/hybrid_text.py` so the Hybrid chat-completions transport omits `response_format` only for `gpt-5-mini` and `gpt-5-mini-2025-08-07`.
- Keep current request behavior unchanged for working Hybrid models such as `gpt-4o-mini-2024-07-18` and `gpt-4.1-mini-2025-04-14`.
- Do not change Hybrid model resolution, lane manifests, lane policy, README/guides/release docs, provider probes, media, or benchmarks in this pass.
- Add unit tests in `tests/test_hybrid_text.py` that capture outbound payloads and prove the gate is applied only to the `gpt-5-mini` family.

## Why This Pass

Preserved evidence shows the current Private project accepts AI-style plain `/v1/chat/completions` requests for the `gpt-5-mini` family but rejects the current Hybrid structured request shape on the same endpoint with `model_unavailable` / HTTP `400`.

The smallest supported repo-side follow-up is to remove the most obvious request-shape difference that is unique to the Hybrid transport while keeping the rest of Hybrid parsing and validation intact.

## Acceptance

- `response_format` is omitted for Hybrid requests using `gpt-5-mini` or `gpt-5-mini-2025-08-07`.
- `response_format` remains present for `gpt-4o-mini-2024-07-18` and `gpt-4.1-mini-2025-04-14`.
- Existing Hybrid model-selection behavior is unchanged.
- Unit tests pass.
- Issue `#31` remains open.
- Any live provider validation is deferred to a later tiny no-media pass.
