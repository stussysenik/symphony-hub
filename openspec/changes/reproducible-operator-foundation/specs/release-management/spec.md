## ADDED Requirements

### Requirement: Repository releases are generated automatically

The system SHALL define automated release management for `symphony-hub` using
semantic-release and semver tags.

#### Scenario: Stable release from main
- **WHEN** a releasable commit lands on `main`
- **THEN** the release workflow computes the next stable semver version and
  publishes a corresponding GitHub release and git tag.

#### Scenario: Prerelease from channel branch
- **WHEN** a releasable commit lands on `next`, `beta`, or `alpha`
- **THEN** the release workflow publishes a prerelease version for that
  channel.

### Requirement: Release automation preserves repository artifacts

The release workflow SHALL update durable release artifacts in the repository
without attempting to publish an npm package.

#### Scenario: Changelog and version are updated
- **WHEN** semantic-release prepares a release
- **THEN** it updates `CHANGELOG.md`, `package.json`, and `package-lock.json`
  to reflect the new version.

#### Scenario: No npm publish occurs
- **WHEN** the release workflow runs
- **THEN** it SHALL not attempt to publish `symphony-hub` to the npm registry.
