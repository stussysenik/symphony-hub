## ADDED Requirements

### Requirement: GitHub repo sync populates a non-runtime catalog

The system SHALL provide a command that imports GitHub repository metadata into
`catalog.projects` without forcing those repos into the active runtime set.

#### Scenario: Sync imports new repos
- **WHEN** an operator runs `sync-projects` for a GitHub owner
- **THEN** newly discovered repos are added under `catalog.projects`
- **AND** existing managed runtime repos remain in `projects`
- **AND** no existing repo entries are deleted

#### Scenario: Sync clones missing repos on demand
- **WHEN** an operator runs `sync-projects --apply --clone-missing`
- **AND** a discovered repo has no local checkout at its configured `repo_root`
- **THEN** the command clones that repo locally
- **AND** the sync report records that the repo was cloned

### Requirement: Catalog repos remain usable for intake

The system SHALL allow repo-backed intake and initiative fanout to resolve repo
definitions from either `projects` or `catalog.projects`.

#### Scenario: Initiative targets a cataloged repo
- **WHEN** a repo exists only in `catalog.projects`
- **THEN** initiative can still build a repo-local task for it
- **AND** intake can use that repo definition if the local checkout exists

### Requirement: Shared Linear override supports cross-repo initiatives

The system SHALL allow intake and initiative to use an explicit Linear project
slug override when the repo entry has no dedicated `linear_project_slug`.

#### Scenario: Repo has no dedicated Linear mapping
- **WHEN** an operator runs intake or initiative with `--linear-project-slug`
- **AND** the target repo has no configured `linear_project_slug`
- **THEN** the command uses the override for the Linear project context
- **AND** the repo can still produce a repo-local issue draft or created issue

#### Scenario: Repo lacks any Linear mapping
- **WHEN** a repo has no configured `linear_project_slug`
- **AND** no override is provided
- **THEN** the command fails or reports a clear actionable error instead of
  silently creating an ungrounded issue
