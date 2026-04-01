## ADDED Requirements

### Requirement: Workflow history is preserved

The system SHALL preserve workflow history by archiving, cancelling, or
superseding issues instead of deleting them to clean the board.

#### Scenario: Work is superseded
- **WHEN** an issue is replaced by a new issue
- **THEN** the original issue remains in the system with a short note linking
  the successor issue.

#### Scenario: Work stops being active
- **WHEN** a ticket is no longer part of the active path
- **THEN** it is moved out of active execution views through state changes, not
  deletion.

### Requirement: Operator docs have a canonical navigation surface

The system SHALL provide a documentation map that tells operators where to start
daily work, where to find process rules, and where change proposals live.

#### Scenario: Operator opens the docs index
- **WHEN** the operator reads the docs map
- **THEN** it points them to the daily startup command, control-loop docs,
  checkpoints, OpenSpec artifacts, and release workflow.

### Requirement: Board minimalism comes from views and gates

The system SHALL keep the active workflow minimal by using narrow states and
saved views rather than deleting artifacts.

#### Scenario: Active board is reviewed
- **WHEN** the operator reviews board configuration guidance
- **THEN** the documented primary views are `Inbox`, `Ready`, `Needs Me`, and
  `Done Recent`.
