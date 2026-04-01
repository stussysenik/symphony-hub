## Context

`symphony-hub` wraps the Symphony engine, local project repos, and the Linear
board. The repo already has working monitoring scripts, checkpointing, and
workflow generation, but operators still need to remember too many commands and
state transitions. At the same time, the repo has no release automation, so
process improvements are hard to version cleanly.

OpenSpec is available locally and can act as the change-management spine for
workflow evolution inside the repo itself.

## Goals / Non-Goals

**Goals:**
- Make `symphony-hub` the obvious place to resume work from.
- Reduce startup friction to one command that surfaces health, queue state, and
  the latest checkpoint.
- Adopt a durable spec workflow for operator/process changes.
- Move release handling from manual tags to semantic-release with semver tags
  and generated changelogs.
- Preserve workflow history while keeping the active board and docs minimal.

**Non-Goals:**
- Rebuild the full Linear board in this change.
- Automate every possible board mutation from the hub repo.
- Replace the existing TUI, dashboard, or monitoring scripts.
- Publish an npm package.

## Decisions

### 1. Keep `symphony-hub` as the canonical operator home

The hub repo remains the source of truth for operator tooling, docs, workflow
templates, OpenSpec artifacts, and release automation. Runtime artifacts stay
outside versioned docs and continue to live in generated directories.

### 2. Add `brief` and `resume` as the operator entrypoint

The fastest path to calmer DX is not a new dashboard. It is a single command
that summarizes:
- health
- active instances
- source/runtime topology
- latest checkpoint
- queue hygiene

`resume` is implemented as an alias of `brief` so the mental model stays small.

### 3. Use OpenSpec for operator-layer change management

OpenSpec is initialized in the repo with Codex tooling enabled. The
`reproducible-operator-foundation` change establishes the first durable
workflow artifact chain:
- proposal
- design
- specs
- tasks

This keeps future process changes traceable and reviewable.

### 4. Use semantic-release for semver tags and GitHub releases

`symphony-hub` is not an npm package, but a tiny Node toolchain is still the
lowest-friction way to automate releases. The chosen release model is:
- `main` => stable releases
- `next`, `beta`, `alpha` => prerelease channels
- GitHub releases + `CHANGELOG.md`
- package version updates without npm publishing

Existing `beta/*` tags remain historical markers. New automation starts from
semver `v*` tags going forward.

### 5. Preserve history and shrink views instead of deleting records

Workflow cleanup should archive or supersede tickets, not delete them. The repo
documentation will keep reinforcing:
- issue = lifecycle truth
- single workpad comment = execution truth
- checkpoint = operator handoff truth

## Risks / Trade-offs

- **Initial release cutoff ambiguity** -> Historical `beta/*` tags do not map to
  semver. The first semantic-release run becomes the new semver baseline.
- **More repo artifacts** -> OpenSpec and release files add structure, but the
  benefit is reproducibility and auditable change management.
- **Release automation can fail on token/config issues** -> Add a workflow file,
  local scripts, and verification guidance so failures are diagnosable.
- **Brief output can become noisy** -> Keep it focused on operator state and
  treat detailed views as drill-down tools, not the default landing page.

## Migration Plan

1. Initialize OpenSpec and commit the first change proposal.
2. Add `brief`/`resume` so operators have one startup command.
3. Add semantic-release config and GitHub workflow.
4. Update docs to point operators to `symphony-hub` as the daily home.
5. Use the new flow to clean the Linear board and create the next issue set.

Rollback is low-risk:
- remove the release workflow if it misbehaves
- keep manual git tagging available
- continue using existing commands if `brief` is insufficient

## Open Questions

- Should future saved Linear views be documented only, or also exported via a
  scriptable configuration artifact?
- Should `brief` eventually surface PR review metadata from GitHub directly, or
  stay tracker-centric?
