## ADDED Requirements

### Requirement: Canonical issue signature governs `Todo`

The system SHALL define one canonical issue signature for Linear issues and use
it as the structural gate for `Todo`.

#### Scenario: Issue is ready for `Todo`
- **WHEN** an issue contains concrete `Context`, `Problem`, `Desired Outcome`,
  `Acceptance Criteria`, `Validation`, and `Assets`
- **AND** required checklist sections contain real checklist items instead of
  placeholders
- **THEN** the issue qualifies as structurally ready for `Todo`

#### Scenario: Issue is incomplete
- **WHEN** a required section is missing or still a placeholder
- **THEN** the issue is not structurally ready for `Todo`

### Requirement: Canonical formatter preserves evidence

The system SHALL provide a formatter/linter that normalizes recognized issue
sections without deleting extra operator-authored context.

#### Scenario: Existing issue is formatted
- **WHEN** an operator formats an existing issue
- **THEN** recognized sections are rewritten in canonical order
- **AND** machine-managed intake blocks are preserved
- **AND** unknown extra sections remain in the body

### Requirement: Queue hygiene surfaces signature drift

The system SHALL expose canonical-signature drift through the normal audit and
diagnosis paths.

#### Scenario: `Todo` issue is structurally incomplete
- **WHEN** the queue audit inspects a `Todo` issue with missing required
  signature sections
- **THEN** it reports the issue as `todo-unready-signature`

#### Scenario: `Todo` issue is semantically ready but not canonical
- **WHEN** the queue audit inspects a `Todo` issue whose content is adequate but
  whose formatting has drifted from canonical structure
- **THEN** it reports the issue as `todo-needs-format`
