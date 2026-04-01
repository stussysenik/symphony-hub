## Overview

The diagnosis loop is the missing middle layer between queue hygiene and new
issue intake:

1. Select one or more existing issues from a configured Linear project.
2. Re-diagnose the target repo against current `origin/<default_branch>`.
3. Reuse the issue as the prompt source instead of starting from raw NLP.
4. Produce a conservative recommendation:
   - keep
   - rewrite
   - move back to `Backlog`
   - mark as materially present on `main` without auto-closing it
5. Persist the diagnosis bundle locally.
6. Only mutate Linear when `--apply` is passed.

## Components

### 1. Operator Surface

`./launch.sh diagnose --project <name> --issue CRE-123 [--apply]`

The public operator command should be explicit about its purpose:

- `intake`: raw request to draft/new issue
- `diagnose`: existing issue to repo-backed recommendation
- `audit`: broad queue hygiene snapshot

### 2. Shared Evidence Path

Diagnosis should reuse the same repo-backed evidence path already used by
intake:

- git fetch / ahead-behind / dirty state
- code-search evidence with paths, lines, and LOC
- authorization / restriction signals
- related issue context

This avoids duplicating repo-analysis logic or creating competing evidence
surfaces.

### 3. Persistence

Each diagnose run writes a local bundle under `diagnoses/` with per-issue
artifacts such as:

- issue snapshot
- intake/evidence snapshot
- diagnosis result
- rendered comment preview

This gives the operator resumable local memory for backlog cleanup and issue
re-queuing work.

### 4. Safe Apply Behavior

Default mode is preview only.

When `--apply` is passed:

- add a `Diagnosis Review` comment
- apply the suggested state if it differs from the current state

Guardrails:

- do not delete issues
- do not auto-mark issues `Done`
- prefer `Backlog` when the issue is stale, vague, or only partially matched

### 5. Conservative Diagnosis

The diagnosis path may use a bounded Codex-backed recommendation, but it must
remain conservative:

- if richer diagnosis does not complete or is incomplete, fall back to
  deterministic heuristics
- use `Todo` only when the issue appears genuinely agent-ready
- use `Backlog` for stale or under-specified tickets

## Non-Goals

- replacing new-issue intake
- automatic issue deletion or silent cleanup
- automatic `Done` transitions without human verification
- mutating product repos beyond safe fetch-based diagnosis
