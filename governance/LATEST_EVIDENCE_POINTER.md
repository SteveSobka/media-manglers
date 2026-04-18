# LATEST_EVIDENCE_POINTER.md

## Status

No repo-promoted evidence pack is currently checked in for this pass.

This file exists to resolve the governance mismatch where repo instructions
expect a latest-evidence pointer, while current evidence for the active
2026-04-17 migration branch still lives in local validation outputs.

## Current Pass Pointer

For the current `wip/python-core-phased-migration-2026-04-17` pass:

- repo-canonical truth still comes from `governance/CURRENT_PROJECT_TRUTH.md`
- repo-visible work status still comes from `TODO.md`
- current implementation reality must be established by the validation runs and
  artifacts produced during the pass

Typical local evidence for this pass may include:

- `test-output\...` smoke/parity output folders
- extracted release-ZIP validation folders under local temp/test output roots
- PowerShell validator output and Python test output captured during the pass

## Repo-Safe Rule

- Treat local evidence folders as reference-only unless they are explicitly
  promoted into tracked repo material.
- Do not infer repo truth from an untracked local evidence folder alone.
- `governance/CURRENT_PROJECT_TRUTH.md` still remains the highest-precedence
  repo truth source.
- This pointer does not redefine truth precedence. It only records where the
  latest pass evidence currently lives when no repo-promoted evidence pack has
  been checked in yet.
- When no repo-promoted evidence pack exists yet, use
  `governance/CURRENT_PROJECT_TRUTH.md`, then `AGENTS.md`, then `TODO.md`,
  and use this pointer only to locate the current pass's local evidence
  surfaces.

## Next Promotion Expectation

When a future pass produces a stable repo-safe evidence summary or manifest,
update this pointer to name that promoted evidence explicitly instead of only
describing the local validation surfaces.
