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
  `Triage`.

### Requirement: Existing issues can be refreshed safely

The system SHALL support refreshing repo diagnosis on an existing issue without
overwriting the human-authored portions of the description.

#### Scenario: Operator refreshes an issue
- **WHEN** the operator runs the intake command with `--issue CRE-123`
- **THEN** the system updates or appends a managed diagnosis block and preserves
  the rest of the issue description.
