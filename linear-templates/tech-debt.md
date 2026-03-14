# Tech Debt / Refactor

## Recommended form fields

- `Title` (property field, required)
- `What is the current pain?` (long text, required)
- `Why is this debt expensive?` (long text, required)
- `Area` (dropdown: frontend, backend, infra, tooling, test suite)
- `Risk level` (dropdown: high, medium, low)
- `Relevant files / systems` (long text, optional)

## Recommended default properties

- Status: `Triage`
- Label: `debt`
- Team: preset if this template belongs to one team only

## Description body

```md
## Problem
Describe the current technical issue or structural weakness.

## Cost
Explain the maintenance, velocity, reliability, or correctness impact.

## Desired end state
What should be simpler, safer, or easier after this work?

## Constraints
Call out migration, compatibility, or rollout concerns.
```
