# Linear Intake Guide

Recommended setup for capturing ideas in Linear without thinking about issue IDs, labels, or routing every time.

This repo's current orchestration model is:

`Triage` -> `Todo` -> `In Progress` -> `Human Review` -> `Done`

Important: Symphony still starts agents from `Todo`. Use `Triage` as the inbox, and move an issue to `Todo` only when it is ready for implementation.

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

## Acceptance Bar for "Agent-Ready"

Move an intake issue from `Triage` to `Todo` only when:

- the title clearly states the change
- the description includes the desired outcome
- attached mockups or screenshots are present if UI work is involved
- the target project/team is correct

## References

- Linear issue templates: https://linear.app/docs/issue-templates
- Linear issue status and Triage: https://linear.app/docs/configuring-workflows
- Linear Triage Intelligence: https://linear.app/docs/product-intelligence
- Linear create-issue URLs: https://linear.app/developers/create-issues-using-linear-new
