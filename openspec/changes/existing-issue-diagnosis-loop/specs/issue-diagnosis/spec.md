## ADDED Requirements

### Requirement: Existing issues can be diagnosed against current repo state

The system SHALL support diagnosing an existing Linear issue against current
repo state without requiring the operator to manually reconstruct the likely
implementation surface.

#### Scenario: Operator previews an issue diagnosis
- **WHEN** the operator runs the diagnose command for an existing issue
- **THEN** the system produces a local diagnosis bundle with repo-backed
  evidence and a conservative queue recommendation
- **AND** it does not mutate the Linear issue by default

### Requirement: Diagnosis mutations remain explicit and safe

The system SHALL require an explicit operator opt-in before writing diagnosis
results back to Linear.

#### Scenario: Operator applies a diagnosis result
- **WHEN** the operator reruns diagnose with `--apply`
- **THEN** the system writes a diagnosis comment to the target issue
- **AND** applies the suggested safe state change if needed
- **AND** does not delete the issue or auto-mark it `Done`

### Requirement: Diagnosis remains conservative under uncertainty

The system SHALL prefer conservative queue actions when the evidence is
insufficient or the issue is not clearly agent-ready.

#### Scenario: Richer diagnosis does not complete
- **WHEN** the richer diagnosis path times out or is incomplete
- **THEN** the system falls back to deterministic heuristics
- **AND** keeps the recommendation in a safe state such as `Backlog` or the
  current non-executing state
