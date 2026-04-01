## Why

The current hub can audit, archive, watch, and manually template Linear work,
but it still assumes a human has already turned a raw request into a decent
issue. That leaves a gap between "I have a natural-language task" and "this is
safe, scoped, and evidence-backed enough to enter the board."

We need a diagnosis-first intake path that:

- starts from a raw natural-language request
- inspects the configured project against current `origin/main`
- gathers concrete code-location evidence
- calls out likely authorization and restriction surfaces
- persists the intake artifact locally so operators do not lose context
- creates or updates a Linear issue only through an explicit `--apply` gate

This keeps the board calm while still making the system feel lightweight and
composable.

## What Changes

- Add a new `./launch.sh intake` operator command.
- Add a `linear-intake.sh` script that converts a raw prompt into a structured
  Linear draft with:
  - repo/default-branch diagnosis
  - related code evidence with file locations and LOC
  - related Linear issue hints
  - authorization / restriction signals
  - project-specific writable/restricted path policy from `projects.yml`
  - a bounded richer compile attempt with deterministic fallback when that
    compile does not finish in time
  - a structured issue body intended for `Triage` by default
- Persist intake runs under a local git-ignored report root.
- Allow refreshing an existing issue's managed intake block without deleting the
  human-authored parts of the description.
- Add docs describing the intake loop and how it differs from execution.

## Impact

- Operators can start from plain English instead of hand-authoring every draft.
- Linear gains stronger intake quality without turning `Todo` into a trash can.
- The hub gets a reproducible handoff surface for intake work, not just runtime
  execution and review work.
