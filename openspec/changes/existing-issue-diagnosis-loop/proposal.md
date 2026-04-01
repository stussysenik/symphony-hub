## Why

The hub can already:

- audit queue hygiene
- draft a new issue from raw NLP intake
- archive stale issues without deleting history

What it still lacks is a first-class loop for existing issues that asks:

- is this already materially implemented on current `main`?
- is it too vague to stay in `Todo`?
- should it be rewritten, superseded, or safely moved back to `Backlog`?

Without that loop, operators either guess from the board or manually run a
series of ad hoc checks. That creates avoidable churn and makes autonomous
backlog hygiene much weaker than new-issue intake.

## What Changes

- Add a new `./launch.sh diagnose` command.
- Add a `linear-diagnose.sh` helper that:
  - starts from an existing Linear issue
  - reuses the repo-backed diagnosis/evidence path
  - persists a local diagnosis bundle under `diagnoses/`
  - recommends a safe queue action such as keep, rewrite, or move to `Backlog`
  - comments on the issue and applies the suggested safe state change only when
    `--apply` is passed
- Keep the diagnosis loop conservative:
  - dry-run by default
  - preserve issue history
  - do not auto-mark work `Done`

## Impact

- Existing issues become diagnosable with the same rigor as new intake.
- The board can be cleaned and re-queued without deleting history or pretending
  vague tickets are executable.
- The hub gains a reusable control-plane primitive for future review, security,
  and environment policy automation.
