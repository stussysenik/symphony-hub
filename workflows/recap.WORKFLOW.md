---
tracker:
  kind: linear
  project_slug: "15ec4aaf8ef1"
  active_states:
    - Todo
    - In Progress
    - Merging
    - Rework
  terminal_states:
    - Closed
    - Cancelled
    - Canceled
    - Duplicate
    - Done
polling:
  interval_ms: 5000
workspace:
  root: /Users/s3nik/Desktop/symphony-hub/workspaces/recap
hooks:
  after_create: |
    MAIN_REPO="/Users/s3nik/Desktop/recap"
    WORKSPACE="$(pwd)"
    ISSUE_ID="$(basename "$WORKSPACE")"
    BRANCH="feature/${ISSUE_ID}"

    cd "$MAIN_REPO" && git fetch origin

    # Remove the empty workspace dir Symphony created, then replace it with a git worktree.
    rmdir "$WORKSPACE"
    git worktree add "$WORKSPACE" -b "$BRANCH" origin/main

    cd "$WORKSPACE"

    # Auto-detect package manager and install dependencies
    if [ -f "package.json" ]; then
      if [ -f "bun.lockb" ]; then
        bun install
      elif [ -f "pnpm-lock.yaml" ]; then
        pnpm install
      elif [ -f "yarn.lock" ]; then
        yarn install
      else
        npm install
      fi
    fi

    # Python projects
    if [ -f "requirements.txt" ]; then
      pip install -r requirements.txt
    elif [ -f "pyproject.toml" ]; then
      pip install -e .
    fi

    # Rust projects
    if [ -f "Cargo.toml" ]; then
      cargo build
    fi

    # Go projects
    if [ -f "go.mod" ]; then
      go mod download
    fi
  before_remove: |
    MAIN_REPO="/Users/s3nik/Desktop/recap"
    WORKSPACE="$(pwd)"
    cd "$MAIN_REPO" 2>/dev/null && git worktree remove "$WORKSPACE" --force 2>/dev/null || true
    git worktree prune 2>/dev/null || true
agent:
  max_concurrent_agents: 2
  max_turns: 20
codex:
  command: codex --config shell_environment_policy.inherit=all --config model_reasoning_effort=xhigh --model gpt-5.3-codex app-server
  approval_policy: never
  thread_sandbox: workspace-write
  turn_sandbox_policy:
    type: workspaceWrite
---

You are working on a Linear ticket `{{ issue.identifier }}` for the **recap** project.

{% if attempt %}
Continuation context:

- This is retry attempt #{{ attempt }} because the ticket is still in an active state.
- Resume from the current workspace state instead of restarting from scratch.
- Do not repeat already-completed investigation or validation unless needed for new code changes.
- Do not end the turn while the issue remains in an active state unless you are blocked by missing required permissions/secrets.
{% endif %}

Issue context:
Identifier: {{ issue.identifier }}
Title: {{ issue.title }}
Current status: {{ issue.state }}
Labels: {{ issue.labels }}
URL: {{ issue.url }}

Description:
{% if issue.description %}
{{ issue.description }}
{% else %}
No description provided.
{% endif %}

{% if has_visual_assets %}
## Visual Context

{{ visual_asset_count }} screenshot(s) attached. CRITICAL: analyze every image before writing code.
Compare current UI against screenshots. These are your acceptance criteria.
{% endif %}

Instructions:

1. This is an unattended orchestration session. Never ask a human to perform follow-up actions.
2. Only stop early for a true blocker (missing required auth/permissions/secrets). If blocked, record it in the workpad and move the issue according to workflow.
3. Final message must report completed actions and blockers only. Do not include "next steps for user".

Work only in the provided repository copy. Do not touch any other path.

## Prerequisite: Linear MCP or `linear_graphql` tool is available

The agent should be able to talk to Linear, either via a configured Linear MCP server or injected `linear_graphql` tool. If none are present, stop and ask the user to configure Linear.

## Default posture

- Start by determining the ticket's current status, then follow the matching flow for that status.
- Start every task by opening the tracking workpad comment and bringing it up to date before doing new implementation work.
- Spend extra effort up front on planning and verification design before implementation.
- Reproduce first: always confirm the current behavior/issue signal before changing code so the fix target is explicit.
- Keep ticket metadata current (state, checklist, acceptance criteria, links).
- Treat a single persistent Linear comment as the source of truth for progress.
- Use that single workpad comment for all progress and handoff notes; do not post separate "done"/summary comments.
- Treat any ticket-authored `Validation`, `Test Plan`, or `Testing` section as non-negotiable acceptance input: mirror it in the workpad and execute it before considering the work complete.
- When meaningful out-of-scope improvements are discovered during execution,
  file a separate Linear issue instead of expanding scope. The follow-up issue
  must include a clear title, description, and acceptance criteria, be placed in
  `Backlog`, be assigned to the same project as the current issue, link the
  current issue as `related`, and use `blockedBy` when the follow-up depends on
  the current issue.
- Move status only when the matching quality bar is met.
- Operate autonomously end-to-end unless blocked by missing requirements, secrets, or permissions.
- Use the blocked-access escape hatch only for true external blockers (missing required tools/auth) after exhausting documented fallbacks.

## Related skills

- `linear`: interact with Linear.
- `commit`: produce clean, logical commits during implementation.
- `push`: keep remote branch current and publish updates.
- `pull`: keep branch updated with latest `origin/main` before handoff.
- `land`: when ticket reaches `Merging`, explicitly open and follow `.codex/skills/land/SKILL.md`, which includes the `land` loop.

## Status map

- `Backlog` -> out of scope for this workflow; do not modify.
- `Todo` -> queued; immediately transition to `In Progress` before active work.
  - Special case: if a PR is already attached, treat as feedback/rework loop (run full PR feedback sweep, address or explicitly push back, revalidate, return to `Human Review`).
- `In Progress` -> implementation actively underway.
- `Human Review` -> PR is attached and validated; waiting on human approval.
- `Merging` -> approved by human; execute the `land` skill flow (do not call `gh pr merge` directly).
- `Rework` -> reviewer requested changes; planning + implementation required.
- `Done` -> terminal state; no further action required.

## Step 0: Determine current ticket state and route

1. Fetch the issue by explicit ticket ID.
2. Read the current state.
3. Route to the matching flow:
   - `Backlog` -> do not modify issue content/state; stop and wait for human to move it to `Todo`.
   - `Todo` -> immediately move to `In Progress`, then ensure bootstrap workpad comment exists (create if missing), then start execution flow.
     - If PR is already attached, start by reviewing all open PR comments and deciding required changes vs explicit pushback responses.
   - `In Progress` -> continue execution flow from current scratchpad comment.
   - `Human Review` -> wait and poll for decision/review updates.
   - `Merging` -> on entry, open and follow `.codex/skills/land/SKILL.md`; do not call `gh pr merge` directly.
   - `Rework` -> run rework flow.
   - `Done` -> do nothing and shut down.
4. Check whether a PR already exists for the current branch and whether it is closed.
   - If a branch PR exists and is `CLOSED` or `MERGED`, treat prior branch work as non-reusable for this run.
   - Create a fresh branch from `origin/main` and restart execution flow as a new attempt.
5. For `Todo` tickets, do startup sequencing in this exact order:
   - `update_issue(..., state: "In Progress")`
   - find/create `## Codex Workpad` bootstrap comment
   - only then begin analysis/planning/implementation work.
6. Add a short comment if state and issue content are inconsistent, then proceed with the safest flow.

## Step 1: Start/continue execution (Todo or In Progress)

1.  Find or create a single persistent scratchpad comment for the issue:
    - Search existing comments for a marker header: `## Codex Workpad`.
    - Ignore resolved comments while searching; only active/unresolved comments are eligible to be reused as the live workpad.
    - If found, reuse that comment; do not create a new workpad comment.
    - If not found, create one workpad comment and use it for all updates.
    - Persist the workpad comment ID and only write progress updates to that ID.
2.  If arriving from `Todo`, do not delay on additional status transitions: the issue should already be `In Progress` before this step begins.
3.  Immediately reconcile the workpad before new edits:
    - Check off items that are already done.
    - Expand/fix the plan so it is comprehensive for current scope.
    - Ensure `Acceptance Criteria` and `Validation` are current and still make sense for the task.
4.  Start work by writing/updating a hierarchical plan in the workpad comment.
5.  Ensure the workpad includes a compact environment stamp at the top as a code fence line:
    - Format: `<host>:<abs-workdir>@<short-sha>`
    - Example: `devbox-01:/home/dev-user/code/workspaces/CRE-32@7bdde33bc`
    - Do not include metadata already inferable from Linear issue fields (`issue ID`, `status`, `branch`, `PR link`).
6.  Add explicit acceptance criteria and TODOs in checklist form in the same comment.
    - If changes are user-facing, include a UI walkthrough acceptance criterion that describes the end-to-end user path to validate.
    - If changes touch app files or app behavior, add explicit app-specific flow checks to `Acceptance Criteria` in the workpad (for example: launch path, changed interaction path, and expected result path).
    - If the ticket description/comment context includes `Validation`, `Test Plan`, or `Testing` sections, copy those requirements into the workpad `Acceptance Criteria` and `Validation` sections as required checkboxes (no optional downgrade).
7.  Run a principal-style self-review of the plan and refine it in the comment.
8.  Before implementing, capture a concrete reproduction signal and record it in the workpad `Notes` section (command/output, screenshot, or deterministic UI behavior).
9.  Run the `pull` skill to sync with latest `origin/main` before any code edits, then record the pull/sync result in the workpad `Notes`.
    - Include a `pull skill evidence` note with:
      - merge source(s),
      - result (`clean` or `conflicts resolved`),
      - resulting `HEAD` short SHA.
10. Compact context and proceed to execution.

## Step 2: Execution phase (Todo -> In Progress -> Human Review)

1.  Determine current repo state (`branch`, `git status`, `HEAD`) and verify the kickoff `pull` sync result is already recorded in the workpad before implementation continues.
2.  If current issue state is `Todo`, move it to `In Progress`; otherwise leave the current state unchanged.
3.  Implement the ticket by following the workpad hierarchical plan.
4.  As work progresses:
    - Run the `commit` skill frequently during execution; avoid large/combined commits.
    - Run the `push` skill after each commit or set of commits (at least once every 2-3 commits; do not defer more than that).
    - Update the workpad incrementally as items complete; do not wait until the end.
    - Keep all workpad updates in the same persisted scratchpad comment.
5.  When user-facing behavior changes occur, capture a concrete validation proof (screenshot, command output, or deterministic UI walkthrough path).
6.  Before handing off:
    - Run all available testing (unit, integration, E2E) and record results in workpad `Validation` section.
    - For web/mobile projects, start the dev server and manually test changed functionality.
    - If linting or formatting tools exist, run them and commit fixes.
7.  When implementation is complete and all acceptance criteria are met:
    - Run a final `push`.
    - Create a PR if one does not exist: `gh pr create --title "{{ issue.title }}" --body "Closes {{ issue.identifier }}"`
    - Add the PR link to the Linear issue attachments.
    - Run the PR feedback sweep protocol (see below).
    - Move issue to `Human Review`.

## PR feedback sweep protocol (required)

When a ticket has an attached PR, run this protocol before moving to `Human Review`:

1. Identify the PR number from issue links/attachments.
2. Gather feedback from all channels:
   - Top-level PR comments (`gh pr view --comments`).
   - Inline review comments (`gh api repos/<owner>/<repo>/pulls/<pr>/comments`).
   - Review summaries/states (`gh pr view --json reviews`).
3. Treat every actionable reviewer comment (human or bot), including inline review comments, as blocking until one of these is true:
   - code/test/docs updated to address it, or
   - explicit, justified pushback reply is posted on that thread.
4. Update the workpad plan/checklist to include each feedback item and its resolution status.
5. Re-run validation after feedback-driven changes and push updates.
6. Repeat this sweep until there are no outstanding actionable comments.

## Blocked-access escape hatch (required behavior)

Use this only when completion is blocked by missing required tools or missing auth/permissions that cannot be resolved in-session.

- GitHub is **not** a valid blocker by default. Always try fallback strategies first (alternate remote/auth mode, then continue publish/review flow).
- Do not move to `Human Review` for GitHub access/auth until all fallback strategies have been attempted and documented in the workpad.
- If a non-GitHub required tool is missing, or required non-GitHub auth is unavailable, move the ticket to `Human Review` with a short blocker brief in the workpad that includes:
  - what is missing,
  - why it blocks required acceptance/validation,
  - exact human action needed to unblock.
- Keep the brief concise and action-oriented; do not add extra top-level comments outside the workpad.

## Step 3: Rework flow (Rework -> In Progress -> Human Review)

1. Read current PR review comments and inline feedback.
2. Update the workpad to reflect required changes.
3. Move issue to `In Progress`.
4. Implement changes following the updated plan.
5. Commit and push frequently.
6. When changes are complete, run PR feedback sweep again.
7. Move back to `Human Review`.

## Step 4: Merging flow (Merging -> Done)

When a ticket reaches `Merging` state (human approved):

1. Open `.codex/skills/land/SKILL.md` if it exists and follow the landing protocol.
2. If no `land` skill exists, use the default merge flow:
   - Verify PR checks are passing.
   - Run `gh pr merge --squash` (or `--merge`/`--rebase` based on project conventions).
   - Delete the feature branch: `git push origin --delete <branch-name>`.
3. Update the Linear issue to `Done` state.
4. Add a final workpad note confirming merge SHA and branch cleanup.

## Core Heuristics

- Prefer the smallest diff that fully resolves the issue.
- Reuse existing abstractions and conventions before adding new structure.
- Keep runtime, monitoring, and operator ergonomics simple and observable.
- Record durable findings where the repository already expects them.

## Project-specific context

Repository: https://github.com/stussysenik/recap.git
Local repo: /Users/s3nik/Desktop/recap
Project: recap
Workspace: /Users/s3nik/Desktop/symphony-hub/workspaces/recap
Workspace strategy: worktree
Default branch: main

When working on this project:
- Follow existing code style and conventions found in the repository.
- Check for CONTRIBUTING.md, README.md, or .github/ documentation for project-specific guidelines.
- If tests exist, ensure they pass before creating PRs.
- If CI/CD workflows exist, ensure they pass before moving to `Human Review`.
- Respect existing directory structure and file organization patterns.
- If the repo already contains issue journals such as `PROGRESS.md` or `LEARNING.md`, append a concise note for this ticket.
