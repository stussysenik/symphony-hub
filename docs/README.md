# Docs Map

`symphony-hub` is the operator home for the Symphony control plane.

## Daily Start

Run this first:

```bash
./launch.sh brief
```

Use this when resuming from previous work:

```bash
./launch.sh resume
```

Those commands are the shortest path to:
- health status
- active runtime state
- topology summary
- latest checkpoint
- queue hygiene

## Core Workflow

- [LINEAR-GOLDEN-RULE.md](../LINEAR-GOLDEN-RULE.md): shortest explanation of the Linear + Symphony loop
- [LINEAR-INTAKE.md](../LINEAR-INTAKE.md): intake setup, templates, archive-first rules, and agent-ready bar
- [LINEAR-WORKFLOW.md](../LINEAR-WORKFLOW.md): full lifecycle for execution, monitoring, and review
- [OPERATIONS.md](../OPERATIONS.md): operator runbook, review loop, checkpoints, and release flow

## Architecture And Decisions

- [ARCHITECTURE.md](./ARCHITECTURE.md): system structure and runtime boundaries
- [DECISIONS.md](./DECISIONS.md): architectural decisions, including archive-first workflow and release strategy
- [CHECKPOINTS.md](./CHECKPOINTS.md): local handoff and resume model
- [ISSUE-SIGNATURE.md](./ISSUE-SIGNATURE.md): canonical Linear issue structure and formatter/linter behavior
- [VISION.md](./VISION.md): multimodal and design-context workflow
- [RESEARCH.md](./RESEARCH.md): research notes from building on Symphony

## Change Management

- [proposal.md](../openspec/changes/reproducible-operator-foundation/proposal.md): current operator-foundation change proposal
- [design.md](../openspec/changes/reproducible-operator-foundation/design.md): design for the operator foundation
- [tasks.md](../openspec/changes/reproducible-operator-foundation/tasks.md): implementation checklist
- [proposal.md](../openspec/changes/diagnosis-first-linear-intake/proposal.md): diagnosis-first intake proposal
- [design.md](../openspec/changes/diagnosis-first-linear-intake/design.md): intake architecture and guardrails
- [tasks.md](../openspec/changes/diagnosis-first-linear-intake/tasks.md): intake implementation checklist
- [proposal.md](../openspec/changes/existing-issue-diagnosis-loop/proposal.md): existing-issue diagnosis proposal
- [design.md](../openspec/changes/existing-issue-diagnosis-loop/design.md): diagnosis loop design and guardrails
- [tasks.md](../openspec/changes/existing-issue-diagnosis-loop/tasks.md): diagnosis implementation checklist
- [proposal.md](../openspec/changes/canonical-issue-signature/proposal.md): canonical issue signature proposal
- [design.md](../openspec/changes/canonical-issue-signature/design.md): issue signature and `Todo` gate design
- [tasks.md](../openspec/changes/canonical-issue-signature/tasks.md): issue signature implementation checklist

## Release And Delivery

- `npm run release:dry-run`: local semantic-release dry run
- `npm run release`: local semantic-release execution
- `.github/workflows/release.yml`: automated GitHub release flow
- `CHANGELOG.md`: generated release history

## Hygiene Helpers

- `./launch.sh audit`: queue hygiene snapshot
- `./launch.sh intake --project <name> --prompt "..."`: draft an evidence-backed `Triage` issue from a raw request
- `./launch.sh initiative --all --prompt "..."`: fan out one initiative prompt across configured repos
- `./launch.sh issuefmt --project <name> --issue <ID>`: canonicalize and lint an existing Linear issue body
- `./launch.sh diagnose --project <name> --issue <ID>`: diagnose an existing issue against current repo state
- `./launch.sh diagnose --project <name> --issue <ID> --apply`: write the diagnosis comment and suggested safe state change
- `./linear-archive.sh --issue <ID>`: archive stale issues without deleting history
- `./launch.sh recover --project <name> --root /Users/s3nik/Desktop/symphony-setup/workspaces`: inspect preserved workspaces before revive/archive decisions

## Board Model

Keep the active human surface small:

- `Inbox`: `Triage`
- `Ready`: `Todo`
- `Needs Me`: `Human Review` + `Merging`
- `Done Recent`: recently landed work

Archive or supersede old paths instead of deleting them.

Move work into `Ready` only after `issuefmt` says the signature is clean.

## Runtime Boundary

- `symphony-hub`: canonical operator repo
- `symphony-setup`: runtime evidence locker for preserved workspaces and logs
- product repos: actual implementation targets

## Code Location Model

Use one code location per lifecycle stage:

- `symphony-hub/workspaces/<project>/<ISSUE>`: current active generation
- product repo `repo_root`: canonical landed code on `main`
- `symphony-setup/workspaces/<project>/<ISSUE>`: preserved past generation or abandoned review candidate

Review rule:

- PR exists: review the PR and optionally verify in `symphony-hub/workspaces/...`
- merged already: inspect the product repo root
- no PR, old generation only: inspect `symphony-setup/...` with `./launch.sh recover`
