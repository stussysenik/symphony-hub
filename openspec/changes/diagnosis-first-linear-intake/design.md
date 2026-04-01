## Overview

The intake flow should be composable and diagnosis-first:

1. Accept a raw prompt plus a target configured project.
2. Fetch current `origin/<default_branch>` for that repo without mutating the
   user's working state.
3. Diagnose repo state and gather code evidence.
4. Query Linear for project metadata and nearby issues.
5. Attempt a richer structured issue compile within a bounded operator-safe
   timeout and fall back to a deterministic diagnosis draft if it does not
   complete.
6. Persist the artifacts locally.
7. Create or update the Linear issue only when `--apply` is passed.
8. Select an existing issue with `--issue` when the operator wants to refresh
   its managed diagnosis block.

## Components

### 1. Input Surface

`./launch.sh intake --project <name> --prompt "..." [--apply]`

Supported raw input modes:

- `--prompt <text>`
- `--prompt-file <path>`
- stdin fallback when piped

### 2. Repo Diagnosis

For the configured project repo:

- fetch `origin/<default_branch>`
- detect current branch
- detect local dirty state
- compute ahead/behind for the local default branch versus remote default

The diagnosis is informational. It must not rewrite the user's branch or pull
their working tree forward.

### 3. Evidence Collection

The intake tool gathers:

- code-search hits based on extracted keywords from the prompt/title
- matched file paths and line numbers
- line counts for matched files
- auth/restriction signals from known patterns
- related Linear issues from the same project

These are hints for scoping and review, not a claim of perfect semantic
understanding.

### 3.5 Project Policy

Each configured project can define intake policy in `projects.yml`:

- `team_key`
- `default_state`
- `writable_paths`
- `restricted_paths`
- `required_checks`
- `notes`

This makes scope and validation expectations versioned instead of implicit.

### 4. Draft Rendering

The rendered issue body must include:

- source prompt
- repo diagnosis
- code evidence
- authorization / restriction evidence
- related Linear context
- a structured draft body

The draft is intentionally biased toward `Triage`, not immediate execution.

The compiler path should prefer a richer Codex-backed draft, but that path must
be bounded so it cannot hang the operator loop. If the richer compile times
out or returns incomplete data, the intake command falls back to a deterministic
draft built from the diagnosis and evidence payload.

### 5. Persistence

Each run writes a local report bundle:

- `request.txt`
- `diagnosis.json`
- `compiled.json`
- `draft.md`
- `linear-response.json` when created

This prevents wasted regenerations and makes intake itself resumable.

### 6. Safe Refresh Of Existing Issues

When the operator targets `--issue CRE-123`, the command prepares a refresh for
that issue in dry-run mode by default.

When the operator adds `--apply`, the command updates only a managed intake
block if the issue already has human-written description content.

If the issue description is empty, the command falls back to a full structured
draft body.

The managed intake block is identified by stable start/end markers so refreshes
replace or prepend only the machine-owned section.

## Guardrails

- default mode is dry-run
- default state is `Triage`
- project policy controls the default writable/restricted surface
- issue creation or refresh mutation is explicit via `--apply`
- existing-issue targeting is explicit via `--issue`
- if `Triage` does not exist on the team, the command resolves that request to
  `Backlog`; other unknown states still fail instead of silently creating
  executable work in the wrong state

## Non-Goals

- full semantic planning or implementation from the intake command
- replacing the Linear workpad during execution
- mutating the product repo beyond safe fetch-based diagnosis
- silently overwriting the human-authored parts of an existing issue
