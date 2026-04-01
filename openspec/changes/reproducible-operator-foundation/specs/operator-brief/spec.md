## ADDED Requirements

### Requirement: Operator can generate a one-command startup brief

The system SHALL provide a hub-level command that summarizes operator state
without requiring the operator to manually run multiple scripts.

#### Scenario: Default startup brief
- **WHEN** the operator runs `./launch.sh brief`
- **THEN** the system outputs health, runtime instance status, condensed
  topology, latest checkpoint information, and Linear queue hygiene.

#### Scenario: Resume alias
- **WHEN** the operator runs `./launch.sh resume`
- **THEN** the system outputs the same information as `./launch.sh brief`.

### Requirement: Brief output tolerates missing local artifacts

The system SHALL still produce a useful startup summary when some local runtime
artifacts are missing.

#### Scenario: No checkpoint exists yet
- **WHEN** the operator runs `./launch.sh brief` and `checkpoints/latest` does
  not exist
- **THEN** the system states that no checkpoint is available and continues with
  the remaining summary sections.

#### Scenario: Linear credentials are unavailable
- **WHEN** the operator runs `./launch.sh brief` without a valid
  `LINEAR_API_KEY`
- **THEN** the system omits the queue report with a clear note instead of
  failing the entire command.

### Requirement: Brief supports scoped queue review

The system SHALL allow queue hygiene to be scoped through the same command
surface used for startup.

#### Scenario: Brief for one project
- **WHEN** the operator runs `./launch.sh brief --project mymind-clone-web`
- **THEN** the queue section only includes the scoped audit output for that
  project.
