# Linear Intake Guide

Recommended setup for capturing ideas in Linear without thinking about issue IDs, labels, or routing every time.

This repo's current orchestration model is:

`Triage` -> `Todo` -> `In Progress` -> `Human Review` -> `Done`

Important: Symphony still starts agents from `Todo`. Use `Triage` as the inbox, and move an issue to `Todo` only when it is ready for implementation.

## Operating Principles

Design the board for three things at once:

- **Velocity**: work should move quickly once it reaches `Todo`.
- **Agency**: agents should have enough context and autonomy to execute without constant human steering.
- **Digital minimalism**: the board should feel calm because views are intentional, not because history was deleted.

Preserve operational history:

- never delete issues that entered the workflow
- archive or move them out of active views instead
- keep comments, workpads, PR links, validation notes, and checkpoints as durable evidence

Minimalism should come from clean states, small labels, and focused saved views, not from losing execution history.

## What to Configure in Linear

### 1. Enable Triage for the team

In Linear:

1. Open `Settings -> Teams -> Issue statuses & automations`
2. Enable `Triage`
3. Keep `Todo` as the "ready for agent" state

This gives you an intake inbox for rough requests without immediately starting an agent.

### 2. Keep the label system small

Use labels for routing and reporting, not taxonomy theater.

Suggested labels:

- Type: `bug`, `feature`, `debt`, `research`
- Surface: `frontend`, `backend`, `infra`, `design`, `mobile`
- Source: `self`, `customer`, `ops`, `sales`

### 3. Create four form templates

Use the blueprints in [`linear-templates/README.md`](linear-templates/README.md):

- [`linear-templates/bug-report.md`](linear-templates/bug-report.md)
- [`linear-templates/feature-request.md`](linear-templates/feature-request.md)
- [`linear-templates/tech-debt.md`](linear-templates/tech-debt.md)
- [`linear-templates/research-spike.md`](linear-templates/research-spike.md)

For each template:

- make `Title` required
- make the primary context field required
- set default status to `Triage`
- set the base label for the template (`bug`, `feature`, `debt`, or `research`)
- optionally preset the team or project if the template belongs to one team only

### 4. Turn on Triage Intelligence

If your Linear plan includes it:

1. Open `Settings -> AI`
2. Enable `Triage Intelligence`
3. Start with suggestions for `team`, `project`, and `labels`
4. Only auto-apply fields after you trust the suggestions

Do not auto-apply priority on day one. It usually creates noise faster than it creates value.

### 5. Configure default templates

Recommended defaults:

- Team members: no forced default, unless one template dominates most work
- Non-team members or intake-heavy teams: use a default form template so the composer never starts blank

## Operational Rule with Symphony

- Put rough requests in `Triage`
- Refine or accept the AI suggestions
- Move to `Todo` when the issue is implementation-ready
- Let Symphony take over from there

If you already know an issue is implementation-ready, create it directly in `Todo`.

## Archive, Don't Delete

When a ticket is no longer the active path:

- move it to a non-executing state such as `Backlog`, `Cancelled`, or another archive state your team uses
- add a short closing note explaining why it stopped or changed
- link any replacement ticket if the work was split or superseded

This keeps the system auditable:

- original intent stays visible
- spec changes stay traceable
- failed attempts become learning material
- operators can reconstruct what happened without guesswork

## Fast Capture Options

### Linear-native

- Press `Alt/Option + C` in Linear to create an issue from a template
- Use pre-filled `linear.new` links for team/project/status defaults

### Repo helper

Use [`linear-new.sh`](linear-new.sh) to open a pre-filled Linear issue composer from the terminal:

```bash
./linear-new.sh --team CRE --status Triage --labels feature,frontend
./linear-new.sh --team CRE --status Todo --title "Add dark mode toggle"
```

The script uses Linear's supported create-issue URLs and lets you pre-fill:

- team
- title
- description
- status
- labels
- project
- template UUID

### Diagnosis-first intake

Use [`linear-intake.sh`](linear-intake.sh) when you only have a raw prompt and
want the hub to draft a better `Triage` issue first:

```bash
./launch.sh intake --project mymind-clone-web \
  --prompt "Polish the search shell focus state and make sure protected flows still read clearly"
```

What it does:

- fetches current `origin/<default_branch>` for the configured repo
- records repo dirty/ahead/behind state
- gathers code hits with file paths, line numbers, and LOC
- scans for likely auth / restriction surfaces
- stamps the draft with the project's configured writable paths, restricted paths, and required checks
- checks for related Linear issues in the same project
- writes a local report bundle under `intakes/`
- attempts a richer Codex-backed spec compile first, then falls back to a deterministic diagnosis draft if that compile does not complete in time
- creates the Linear issue only if you pass `--apply`
- resolves `Triage` to `Backlog` automatically if the team does not expose a `Triage` state

Use this for `Triage` intake. Do not treat it as a replacement for tightening
the issue before `Todo`.

If you already have an issue and want the hub to investigate it against the
current repo state, use the diagnosis loop:

```bash
./launch.sh diagnose --project mymind-clone-web --issue CRE-123
./launch.sh diagnose --project mymind-clone-web --issue CRE-123 --apply
```

The first command previews the diagnosis and writes a local bundle under
`diagnoses/`. Adding `--apply` writes a `Diagnosis Review` comment and applies
the suggested safe queue state change.

Use `diagnose` when the issue already exists and the operator question is:
"is this implemented, stale, too vague, or ready to re-queue?" Use `intake`
when the work still starts as a raw request and needs to become a clean issue.

If the requested state does not exist on the team yet, the command prints the
resolved fallback state. In the current board shape, asking for `Triage` may
resolve to `Backlog` until Triage is enabled in Linear.

## Acceptance Bar for "Agent-Ready"

Move an intake issue from `Triage` to `Todo` only when:

- the title clearly states the change
- the issue uses a stable structure such as `Context`, `Problem`, `Desired Outcome`, `Acceptance Criteria`, `Validation`, and `Assets`
- the description includes the desired outcome
- attached mockups or screenshots are present if UI work is involved
- the target project/team is correct

## References

- Linear issue templates: https://linear.app/docs/issue-templates
- Linear issue status and Triage: https://linear.app/docs/configuring-workflows
- Linear Triage Intelligence: https://linear.app/docs/product-intelligence
- Linear create-issue URLs: https://linear.app/developers/create-issues-using-linear-new
