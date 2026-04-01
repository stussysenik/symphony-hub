# Agent-Ready Project Walkthrough

Use this when you want a Linear issue to be the full execution spec for an
agent run, not just a rough intake note.

This template is intentionally richer than the basic `feature-request` or
`bug-report` forms. It is meant for work that should move from `Triage` or
`Backlog` into `Todo` and then run cleanly through the Symphony loop.

## Recommended form fields

- `Title` (property field, required)
- `Context` (long text, required)
- `Problem` (long text, required)
- `Desired outcome` (long text, required)
- `Acceptance criteria` (long text, required)
- `Validation plan` (long text, required)
- `Assets / links` (long text, optional)
- `Surface area` (dropdown: frontend, backend, infra, design, mobile, cross-product)
- `Type` (dropdown: feature, bug, debt, research)

## Recommended default properties

- Status: `Triage`
- Team: preset if this template belongs to one team only
- Project: preset if this template belongs to one project only
- Labels: keep minimal, usually one `type` label and one `surface` label

## Description body

```md
## Context
What area of the product or system this touches.
Mention the current feature, prior issue, existing implementation, or reason this matters now.

## Problem
What is wrong, weak, missing, or unclear today?
Describe the actual gap, not just the desired solution.

## Desired Outcome
What should be true when this is complete?
Describe the user-visible or system-visible result.

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Validation
- [ ] Manual flow to verify
- [ ] Automated check / command / test if relevant
- [ ] Screenshot or visual verification if UI work is involved

## Assets
- Linear attachments
- Screenshots
- Figma links
- Related issues / PRs / docs

## Non-Goals
- Explicitly list what this issue should not expand into

## Risks / Notes
- Any rollout concern, edge case, or constraint the agent should respect
```

## Full example

### Example title

`Polish search shell active state across desktop and mobile`

### Example body

```md
## Context
The search shell is a core repeated interaction on both desktop and mobile in `mymind-clone-web`.
Recent UI work improved the general shell, but the focused/active state still reads as a blunt rectangle and does not feel integrated with the rest of the product.
This is high-frequency UI, so the motion and visual treatment need to feel intentional and restrained.

## Problem
The current search active state is visually heavy, abrupt, and not well integrated with the surrounding shell.
The desktop and mobile variants do not feel like one coherent system.
The interaction works, but the design quality is below the standard we want for a frequently used primary control.

## Desired Outcome
The desktop and mobile search bars should feel refined, calm, and integrated with the app shell.
The active state should communicate focus clearly without looking like a separate box pasted on top of the interface.
Accessory controls should appear and disappear smoothly, and reduced-motion users should still get a clear state change.

## Acceptance Criteria
- [ ] Focused desktop and mobile search bars no longer read as a blunt rectangle.
- [ ] Active-state motion stays restrained: transform / opacity / shadow only, under 300ms.
- [ ] Query accessory controls appear and disappear continuously, without abrupt snapping.
- [ ] Reduced-motion users get the same state transition without unnecessary motion.
- [ ] Desktop and mobile treatments feel like one coherent interaction family.

## Validation
- [ ] Open `/` and focus the desktop search bar.
- [ ] Open the mobile view and focus the bottom search bar.
- [ ] Type text, clear text, and confirm the active treatment stays polished in both themes.
- [ ] Run relevant tests for the touched UI surface.
- [ ] Capture a verification screenshot for desktop and mobile.

## Assets
- Attach current screenshots of desktop and mobile search states.
- Attach target references or motion references if available.
- Link related issue(s) that previously touched the search shell.

## Non-Goals
- Do not redesign the search ranking logic.
- Do not rebuild the global header layout.
- Do not introduce new experimental interaction patterns outside the search shell.

## Risks / Notes
- This control is high-frequency, so avoid loud or novelty-driven motion.
- Keep the implementation local to the search shell and its supporting styles/hooks unless a shared primitive clearly needs refinement.
```

## How this should flow in Linear

Use this lifecycle:

- `Triage` or `Backlog`: capture and refine
- `Todo`: agent-ready execution trigger
- `In Progress`: active agent run
- `Human Review`: PR ready for review
- `Merging`: approved and landing
- `Done`: merged

Archive or supersede stale paths instead of deleting them.

## What the agent should mirror

Once the issue moves to `Todo`, the agent should mirror the important parts into
one `## Codex Workpad` comment:

- plan
- acceptance criteria
- validation checklist
- environment stamp
- progress updates
- blocker notes if needed

That keeps the Linear issue as the mission spec and the workpad as the running
execution memory.
