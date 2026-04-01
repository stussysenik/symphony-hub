## ADDED Requirements

### Requirement: Raw prompts can be turned into evidence-backed intake drafts

The system SHALL support turning a raw natural-language request into a
structured Linear draft backed by repo diagnosis and code evidence.

#### Scenario: Operator drafts an issue from a raw request
- **WHEN** the operator runs the intake command for a configured project
- **THEN** the system produces a structured draft containing the source prompt,
  repo diagnosis, code evidence, authorization / restriction signals, and the
  project-specific writable/restricted path policy.

### Requirement: Intake runs persist locally before issue creation

The system SHALL persist intake artifacts locally so operators can resume or
inspect prior diagnosis work without regenerating it.

#### Scenario: Intake run completes in dry-run mode
- **WHEN** the operator runs the intake command without `--apply`
- **THEN** the system writes a local report bundle with the request, draft, and
  machine-readable diagnosis data.

### Requirement: Issue creation is explicitly gated

The system SHALL require an explicit operator action before a drafted intake is
created as a Linear issue.

#### Scenario: Operator does not pass apply
- **WHEN** the intake command runs without `--apply`
- **THEN** it does not create or mutate any Linear issue.

#### Scenario: Operator opts in to creation
- **WHEN** the intake command runs with `--apply`
- **THEN** it creates the issue in the requested state, defaulting to
  `Triage`, or `Backlog` when the team does not expose `Triage`.

#### Scenario: Operator targets an existing issue without apply
- **WHEN** the operator runs the intake command with `--issue CRE-123` and
  omits `--apply`
- **THEN** the system does not mutate the Linear issue and only renders the
  preview plus local report bundle.

### Requirement: Existing issues can be refreshed safely

The system SHALL support refreshing repo diagnosis on an existing issue without
overwriting the human-authored portions of the description.

#### Scenario: Operator refreshes an issue
- **WHEN** the operator runs the intake command with `--issue CRE-123 --apply`
- **THEN** the system updates or appends a managed diagnosis block and preserves
  the rest of the issue description.

#### Scenario: Operator refreshes an empty issue description
- **WHEN** the operator runs the intake command with `--issue CRE-123 --apply`
  and the existing issue description is empty
- **THEN** the system falls back to rendering the full structured draft body.

### Requirement: Intake compilation remains bounded

The system SHALL keep the intake compile path bounded so it does not hang the
operator loop.

#### Scenario: Richer compile does not complete in time
- **WHEN** the richer intake compile path times out or returns incomplete data
- **THEN** the system falls back to a deterministic diagnosis-backed draft and
  still writes the local report bundle.
