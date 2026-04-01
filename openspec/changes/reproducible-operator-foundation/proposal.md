## Why

`symphony-hub` is now the canonical operator repo, but the current workflow still
depends on too much operator memory. Startup, resume, release handling, and
board governance need one reproducible control plane before the Linear board can
be cleaned up safely.

## What Changes

- Add a one-command operator brief/resume surface to `launch.sh`.
- Adopt OpenSpec in the repo so workflow changes are proposed, designed, and
  tracked through durable artifacts instead of ad hoc notes.
- Add semantic-release automation for `symphony-hub` with semver tags,
  changelog generation, and GitHub releases.
- Add a canonical documentation map and clarify archive-first workflow
  governance for Linear-driven execution.

## Capabilities

### New Capabilities
- `operator-brief`: Generate a single startup/resume summary for operators.
- `release-management`: Version and publish `symphony-hub` changes through
  semantic-release without npm publishing.
- `workflow-governance`: Preserve workflow history, document state ownership,
  and keep the active operator surface minimal.

### Modified Capabilities
- None.

## Impact

- `launch.sh` command surface and operator workflow docs
- repo metadata and GitHub Actions release automation
- OpenSpec scaffolding under `.codex/` and `openspec/`
- documentation entrypoints for daily operator use and Linear board governance
